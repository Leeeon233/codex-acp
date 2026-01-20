import { chmodSync, existsSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

if (process.platform !== "win32") {
  const packageDir = path.dirname(fileURLToPath(import.meta.url));
  const binaryPath = path.join(packageDir, "bin", "acp-extension-codex");

  if (existsSync(binaryPath)) {
    try {
      const st = statSync(binaryPath);
      if ((st.mode & 0o111) === 0) {
        chmodSync(binaryPath, st.mode | 0o111);
      }
    } catch {
      // Best-effort: if chmod fails, the CLI wrapper will surface the error.
    }
  }
}

