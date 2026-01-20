#!/usr/bin/env bash
set -euo pipefail

# Used in CI, extract here for readability

# Script to create platform-specific npm packages from release artifacts
# Usage: create-platform-packages.sh <artifacts-dir> <output-dir> <version>

ARTIFACTS_DIR="${1:?Missing artifacts directory}"
OUTPUT_DIR="${2:?Missing output directory}"
VERSION="${3:?Missing version}"
NPM_BASE_NAME="${NPM_BASE_NAME:-acp-extension-codex}"

echo "Creating platform-specific npm packages..."
echo "Artifacts: $ARTIFACTS_DIR"
echo "Output: $OUTPUT_DIR"
echo "Version: $VERSION"
echo "Base package: $NPM_BASE_NAME"
echo

mkdir -p "$OUTPUT_DIR"

# Define platform mappings: target:os:arch:binary-extension
# Note: We only package gnu variants for Linux
platforms=(
  "aarch64-apple-darwin:darwin:arm64:"
  "x86_64-apple-darwin:darwin:x64:"
  "x86_64-unknown-linux-gnu:linux:x64:"
  "aarch64-unknown-linux-gnu:linux:arm64:"
  "x86_64-pc-windows-msvc:win32:x64:.exe"
  "aarch64-pc-windows-msvc:win32:arm64:.exe"
)

for entry in "${platforms[@]}"; do
  IFS=":" read -r target os arch ext <<< "$entry"

  # Determine archive extension
  if [[ "$os" == "win32" ]]; then
    archive_ext="zip"
  else
    archive_ext="tar.gz"
  fi

  # Find and extract the archive
  archive_path=$(find "$ARTIFACTS_DIR" -name "*-${target}.${archive_ext}" | head -n 1)

  if [[ -z "$archive_path" ]]; then
    echo "⚠️  Warning: No archive found for target $target"
    continue
  fi

  echo "📦 Processing $target from $(basename "$archive_path")"

  # Create package name
  pkg_name="${NPM_BASE_NAME}-${os}-${arch}"
  pkg_dir="$OUTPUT_DIR/${pkg_name}"
  mkdir -p "${pkg_dir}/bin"

  # Extract binary
  if [[ "$archive_ext" == "zip" ]]; then
    unzip -q -j "$archive_path" "acp-extension-codex${ext}" -d "${pkg_dir}/bin/"
  else
    tar xzf "$archive_path" -C "${pkg_dir}/bin/" "acp-extension-codex${ext}"
  fi

  # Make binary executable (important for Unix-like systems)
  if [[ "$os" != "win32" ]]; then
    chmod 755 "${pkg_dir}/bin/acp-extension-codex${ext}"
    if [[ ! -x "${pkg_dir}/bin/acp-extension-codex${ext}" ]]; then
      echo "❌ Error: binary is not executable: ${pkg_dir}/bin/acp-extension-codex${ext}"
      exit 1
    fi
  fi

  # Create package.json from template
  export PACKAGE_NAME="$pkg_name"
  export VERSION="$VERSION"
  export OS="$os"
  export ARCH="$arch"

  # Find the template relative to this script
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  TEMPLATE_PATH="$SCRIPT_DIR/../template/package.json"
  TEMPLATE_SCRIPT="$SCRIPT_DIR/../template/ensure-executable.mjs"

  if command -v envsubst >/dev/null 2>&1; then
    envsubst < "$TEMPLATE_PATH" > "${pkg_dir}/package.json"
  else
    TEMPLATE_PATH="$TEMPLATE_PATH" OUT_PATH="${pkg_dir}/package.json" node - <<'NODE'
const fs = require("fs");

const templatePath = process.env.TEMPLATE_PATH;
const outPath = process.env.OUT_PATH;
const required = ["PACKAGE_NAME", "VERSION", "OS", "ARCH"];
for (const k of required) {
  if (!process.env[k]) throw new Error(`Missing ${k}`);
}
const vars = {
  PACKAGE_NAME: process.env.PACKAGE_NAME,
  VERSION: process.env.VERSION,
  OS: process.env.OS,
  ARCH: process.env.ARCH,
};

let s = fs.readFileSync(templatePath, "utf8");
for (const [k, v] of Object.entries(vars)) {
  s = s.split(`\${${k}}`).join(v);
}
fs.writeFileSync(outPath, s);
NODE
  fi

  # Copy helper script used by prepack/postinstall (best-effort chmod fallback)
  cp "$TEMPLATE_SCRIPT" "${pkg_dir}/ensure-executable.mjs"

  # Update bin field for Windows to include .exe extension
  if [[ "$os" == "win32" ]]; then
    # Use sed to update the bin path in package.json
    sed -i.bak 's|"bin/acp-extension-codex"|"bin/acp-extension-codex.exe"|' "${pkg_dir}/package.json"
    rm "${pkg_dir}/package.json.bak"
  fi

  echo "   ✓ Created package: ${pkg_name}"
done

echo
echo "✅ Platform packages created in: $OUTPUT_DIR"
ls -1 "$OUTPUT_DIR"
