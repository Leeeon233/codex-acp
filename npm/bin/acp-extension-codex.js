#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";

// Map Node.js platform/arch to package names
function getPlatformPackage() {
  const platform = process.platform;
  const arch = process.arch;
  const baseName = "acp-extension-codex";

  const platformMap = {
    darwin: {
      arm64: `${baseName}-darwin-arm64`,
      x64: `${baseName}-darwin-x64`,
    },
    linux: {
      arm64: `${baseName}-linux-arm64`,
      x64: `${baseName}-linux-x64`,
    },
    win32: {
      arm64: `${baseName}-win32-arm64`,
      x64: `${baseName}-win32-x64`,
    },
  };

  const packages = platformMap[platform];
  if (!packages) {
    console.error(`Unsupported platform: ${platform}`);
    process.exit(1);
  }

  const packageName = packages[arch];
  if (!packageName) {
    console.error(`Unsupported architecture: ${arch} on ${platform}`);
    process.exit(1);
  }

  return packageName;
}

// Locate the binary
function getBinaryPath() {
  const packageName = getPlatformPackage();
  const binaryName =
    process.platform === "win32"
      ? "acp-extension-codex.exe"
      : "acp-extension-codex";

  try {
    // Try to resolve the platform-specific package
    const binaryPath = fileURLToPath(
      import.meta.resolve(`${packageName}/bin/${binaryName}`),
    );

    if (existsSync(binaryPath)) {
      return binaryPath;
    }
  } catch (e) {
    console.error(`Error resolving package: ${e}`);
    // Package not found
  }

  console.error(
    `Failed to locate ${packageName} binary. This usually means the optional dependency was not installed.`,
  );
  console.error(`Platform: ${process.platform}, Architecture: ${process.arch}`);
  process.exit(1);
}

// Execute the binary
function run() {
  const binaryPath = getBinaryPath();
  const result = spawnSync(binaryPath, process.argv.slice(2), {
    stdio: "inherit",
    windowsHide: true,
  });

  if (result.error) {
    console.error(`Failed to execute ${binaryPath}:`, result.error);
    process.exit(1);
  }

  process.exit(result.status || 0);
}

run();
