#!/usr/bin/env node

import { existsSync } from "node:fs";
import process from "node:process";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const repoRoot = resolve(__dirname, "..");

function parseArgs(argv) {
  const args = {
    cwd: process.cwd(),
    auth: "auto",
    timeoutMs: 60_000,
    verbose: false,
    agent: null,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = () => {
      const value = argv[++i];
      if (!value) {
        throw new Error(`Missing value for ${arg}`);
      }
      return value;
    };

    if (arg === "--cwd") {
      args.cwd = resolve(next());
    } else if (arg === "--auth") {
      args.auth = next();
    } else if (arg === "--timeout") {
      args.timeoutMs = Number(next()) * 1000;
    } else if (arg === "--agent") {
      args.agent = next();
    } else if (arg === "--verbose") {
      args.verbose = true;
    } else if (arg === "--help" || arg === "-h") {
      printHelp();
      process.exit(0);
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  if (!Number.isFinite(args.timeoutMs) || args.timeoutMs <= 0) {
    throw new Error("--timeout must be a positive number of seconds");
  }

  return args;
}

function printHelp() {
  console.log(`Usage: node script/acp-new-session.mjs [options]

Starts the local Codex ACP agent and calls initialize + session/new over JSON-RPC.

Options:
  --cwd <path>       Session cwd. Defaults to the current working directory.
  --auth <method>   auto | none | openai-api-key | codex-api-key | chatgpt.
                    Defaults to auto. auto uses CODEX_API_KEY, then OPENAI_API_KEY, if present.
  --agent <path>    ACP agent executable. Defaults to target/debug/acp-extension-codex,
                    falling back to "cargo run --quiet --bin acp-extension-codex --".
  --timeout <sec>   Per-request timeout in seconds. Defaults to 60.
  --verbose         Print JSON-RPC notifications and agent-side requests.
`);
}

function defaultAgentCommand() {
  const debugBinary = resolve(repoRoot, "target/debug/acp-extension-codex");
  if (existsSync(debugBinary)) {
    return { command: debugBinary, args: [] };
  }
  return {
    command: "cargo",
    args: ["run", "--quiet", "--bin", "acp-extension-codex", "--"],
  };
}

function requestedAuthMethod(auth) {
  if (auth === "none") {
    return null;
  }
  if (auth === "auto") {
    if (process.env.CODEX_API_KEY) {
      return "codex-api-key";
    }
    if (process.env.OPENAI_API_KEY) {
      return "openai-api-key";
    }
    return null;
  }
  if (["openai-api-key", "codex-api-key", "chatgpt"].includes(auth)) {
    return auth;
  }
  throw new Error(`Unsupported --auth value: ${auth}`);
}

class JsonRpcProcess {
  constructor(child, { timeoutMs, verbose }) {
    this.child = child;
    this.timeoutMs = timeoutMs;
    this.verbose = verbose;
    this.nextId = 1;
    this.pending = new Map();
    this.buffer = "";
    this.closed = false;

    child.stdout.setEncoding("utf8");
    child.stdout.on("data", (chunk) => this.handleStdout(chunk));
    child.stderr.on("data", (chunk) => process.stderr.write(chunk));
    child.on("exit", (code, signal) => this.rejectAll(
      new Error(`ACP process exited with code ${code ?? "null"} signal ${signal ?? "null"}`),
    ));
    child.on("error", (error) => this.rejectAll(error));
  }

  request(method, params) {
    if (this.closed) {
      return Promise.reject(new Error("ACP process is closed"));
    }

    const id = this.nextId++;
    const message = { jsonrpc: "2.0", id, method, params };
    const payload = `${JSON.stringify(message)}\n`;

    const promise = new Promise((resolvePromise, rejectPromise) => {
      const timeout = setTimeout(() => {
        this.pending.delete(id);
        rejectPromise(new Error(`Timed out waiting for ${method}`));
      }, this.timeoutMs);

      this.pending.set(id, {
        method,
        resolve: resolvePromise,
        reject: rejectPromise,
        timeout,
      });
    });

    this.child.stdin.write(payload);
    return promise;
  }

  handleStdout(chunk) {
    this.buffer += chunk;

    while (true) {
      const newline = this.buffer.indexOf("\n");
      if (newline === -1) {
        return;
      }

      const line = this.buffer.slice(0, newline).trim();
      this.buffer = this.buffer.slice(newline + 1);
      if (line.length === 0) {
        continue;
      }

      let message;
      try {
        message = JSON.parse(line);
      } catch (error) {
        console.error("Failed to parse ACP JSON line:", line);
        console.error(error);
        continue;
      }

      this.handleMessage(message);
    }
  }

  handleMessage(message) {
    if (message.id !== undefined && message.method) {
      this.handleAgentRequest(message);
      return;
    }

    if (message.id !== undefined) {
      const pending = this.pending.get(message.id);
      if (!pending) {
        if (this.verbose) {
          console.error("Received response for unknown id:", message);
        }
        return;
      }

      clearTimeout(pending.timeout);
      this.pending.delete(message.id);

      if (message.error) {
        pending.reject(Object.assign(
          new Error(`${pending.method} failed: ${message.error.message ?? "JSON-RPC error"}`),
          { rpcError: message.error },
        ));
      } else {
        pending.resolve(message.result ?? null);
      }
      return;
    }

    if (message.method && this.verbose) {
      console.error("notification:", JSON.stringify(message));
    }
  }

  handleAgentRequest(message) {
    if (this.verbose) {
      console.error("agent request:", JSON.stringify(message));
    }

    if (message.method === "session/request_permission") {
      const option = message.params?.options?.find((candidate) => candidate.kind === "allow_once")
        ?? message.params?.options?.[0];

      if (option?.optionId) {
        this.respond(message.id, {
          outcome: {
            outcome: "selected",
            optionId: option.optionId,
          },
        });
        return;
      }
    }

    this.respondError(message.id, -32601, `Method not found: ${message.method}`);
  }

  respond(id, result) {
    this.child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id, result })}\n`);
  }

  respondError(id, code, message) {
    this.child.stdin.write(`${JSON.stringify({
      jsonrpc: "2.0",
      id,
      error: { code, message },
    })}\n`);
  }

  async close() {
    this.closed = true;
    this.child.stdin.end();

    if (this.child.exitCode === null) {
      this.child.kill();
    }
  }

  rejectAll(error) {
    this.closed = true;
    for (const [id, pending] of this.pending.entries()) {
      clearTimeout(pending.timeout);
      pending.reject(error);
      this.pending.delete(id);
    }
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const agentCommand = args.agent
    ? { command: args.agent, args: [] }
    : defaultAgentCommand();

  const child = spawn(agentCommand.command, agentCommand.args, {
    cwd: repoRoot,
    env: process.env,
    stdio: ["pipe", "pipe", "pipe"],
  });

  const rpc = new JsonRpcProcess(child, {
    timeoutMs: args.timeoutMs,
    verbose: args.verbose,
  });

  try {
    console.log(`ACP command: ${agentCommand.command} ${agentCommand.args.join(" ")}`.trim());
    console.log(`Session cwd: ${args.cwd}`);

    const initialize = await rpc.request("initialize", {
      protocolVersion: 1,
      clientCapabilities: {},
      clientInfo: {
        name: "codex-acp-local-smoke",
        version: "0.0.0",
      },
    });

    console.log("initialize result:");
    console.log(JSON.stringify(initialize, null, 2));

    const authMethod = requestedAuthMethod(args.auth);
    if (authMethod) {
      const authenticate = await rpc.request("authenticate", {
        methodId: authMethod,
      });
      console.log(`authenticate (${authMethod}) result:`);
      console.log(JSON.stringify(authenticate, null, 2));
    } else {
      console.log("authenticate skipped");
    }

    const newSession = await rpc.request("session/new", {
      cwd: args.cwd,
      mcpServers: [],
    });

    console.log("session/new result:");
    console.log(JSON.stringify(newSession, null, 2));
    console.log(`created sessionId: ${newSession.sessionId}`);
  } finally {
    await rpc.close();
  }
}

main().catch((error) => {
  console.error(error.message);
  if (error.rpcError) {
    console.error(JSON.stringify(error.rpcError, null, 2));
  }
  process.exitCode = 1;
});
