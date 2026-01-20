#!/usr/bin/env bash
set -euo pipefail

# Used in CI, extract here for readability

# Script to update version in base package.json
# Usage: update-base-package.sh <version>

VERSION="${1:?Missing version}"
BASE_PACKAGE_DIR="${BASE_PACKAGE_DIR:-}"

echo "Updating base package.json to version $VERSION..."

# Find the package.json relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -n "$BASE_PACKAGE_DIR" ]]; then
  PACKAGE_JSON="$BASE_PACKAGE_DIR/package.json"
else
  PACKAGE_JSON="$SCRIPT_DIR/../package.json"
fi

if [[ ! -f "$PACKAGE_JSON" ]]; then
  echo "❌ Error: package.json not found at $PACKAGE_JSON"
  exit 1
fi

# Update version in base package.json
sed -i.bak "s/\"version\": \".*\"/\"version\": \"$VERSION\"/" "$PACKAGE_JSON"

# Update optionalDependencies versions
sed -i.bak "s/\"acp-extension-codex-darwin-arm64\": \".*\"/\"acp-extension-codex-darwin-arm64\": \"$VERSION\"/" "$PACKAGE_JSON"
sed -i.bak "s/\"acp-extension-codex-darwin-x64\": \".*\"/\"acp-extension-codex-darwin-x64\": \"$VERSION\"/" "$PACKAGE_JSON"
sed -i.bak "s/\"acp-extension-codex-linux-arm64\": \".*\"/\"acp-extension-codex-linux-arm64\": \"$VERSION\"/" "$PACKAGE_JSON"
sed -i.bak "s/\"acp-extension-codex-linux-x64\": \".*\"/\"acp-extension-codex-linux-x64\": \"$VERSION\"/" "$PACKAGE_JSON"
sed -i.bak "s/\"acp-extension-codex-win32-arm64\": \".*\"/\"acp-extension-codex-win32-arm64\": \"$VERSION\"/" "$PACKAGE_JSON"
sed -i.bak "s/\"acp-extension-codex-win32-x64\": \".*\"/\"acp-extension-codex-win32-x64\": \"$VERSION\"/" "$PACKAGE_JSON"

# Remove backup file
rm -f "$PACKAGE_JSON.bak"

echo "✅ Updated package.json:"
cat "$PACKAGE_JSON"
