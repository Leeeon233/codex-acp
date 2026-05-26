import { chmodSync, existsSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

if (process.platform !== "win32") {
  const packageDir = path.dirname(fileURLToPath(import.meta.url));
  const executablePaths = [
    path.join(packageDir, "bin", "acp-extension-codex"),
    path.join(packageDir, "codex-resources", "bwrap"),
  ];

  for (const executablePath of executablePaths) {
    if (!existsSync(executablePath)) continue;
    try {
      const st = statSync(executablePath);
      if ((st.mode & 0o111) === 0) {
        chmodSync(executablePath, st.mode | 0o111);
      }
    } catch {
      // Best-effort: if chmod fails, the CLI wrapper will surface the error.
    }
  }
}
