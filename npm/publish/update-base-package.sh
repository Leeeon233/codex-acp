#!/usr/bin/env bash
set -euo pipefail

# Used in CI, extract here for readability

# Script to update version in base package.json
# Usage: update-base-package.sh <version>

VERSION="${1:?Missing version}"
NPM_BASE_NAME="${NPM_BASE_NAME:-acp-extension-codex}"

echo "Updating base package.json to version $VERSION..."
echo "Base package name: $NPM_BASE_NAME"

# Find the package.json relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_JSON="$SCRIPT_DIR/../package.json"

if [[ ! -f "$PACKAGE_JSON" ]]; then
  echo "❌ Error: package.json not found at $PACKAGE_JSON"
  exit 1
fi

PACKAGE_JSON="$PACKAGE_JSON" VERSION="$VERSION" NPM_BASE_NAME="$NPM_BASE_NAME" node --input-type=module - <<'NODE'
import fs from "node:fs";

const pkgPath = process.env.PACKAGE_JSON;
const version = process.env.VERSION;
const baseName = process.env.NPM_BASE_NAME;

if (!pkgPath) throw new Error("Missing PACKAGE_JSON");
if (!version) throw new Error("Missing VERSION");
if (!baseName) throw new Error("Missing NPM_BASE_NAME");

const pkg = JSON.parse(fs.readFileSync(pkgPath, "utf8"));
pkg.name = baseName;
pkg.version = version;

const platformPkgs = [
  `${baseName}-darwin-arm64`,
  `${baseName}-darwin-x64`,
  `${baseName}-linux-arm64`,
  `${baseName}-linux-x64`,
  `${baseName}-win32-arm64`,
  `${baseName}-win32-x64`,
];

pkg.optionalDependencies = Object.fromEntries(platformPkgs.map((n) => [n, version]));
fs.writeFileSync(pkgPath, JSON.stringify(pkg, null, 2) + "\n");
NODE

echo "✅ Updated package.json:"
cat "$PACKAGE_JSON"
