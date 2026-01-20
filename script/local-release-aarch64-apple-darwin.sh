#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TARGET="aarch64-apple-darwin"
BINARY_NAME="acp-extension-codex"

VERSION="${VERSION:-}"
if [[ -z "$VERSION" ]]; then
  VERSION="$(grep -m1 "^version" "$ROOT_DIR/Cargo.toml" | sed 's/.*"\(.*\)".*/\1/')"
fi
if [[ -z "$VERSION" ]]; then
  echo "❌ Failed to determine version from Cargo.toml (set VERSION=... to override)" >&2
  exit 1
fi

if [[ "$VERSION" == *"\""* || "$VERSION" == *"="* || "$VERSION" =~ [[:space:]] ]]; then
  echo "❌ Invalid VERSION parsed from Cargo.toml: $VERSION" >&2
  echo "   Tip: set VERSION=0.0.0 to override." >&2
  exit 1
fi

RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/npm-packages/.local-release/$RUN_ID}"
NPM_CACHE_DIR="${NPM_CACHE_DIR:-$OUT_DIR/.npm-cache}"

ARTIFACTS_DIR="$OUT_DIR/artifacts"
PLATFORM_PKGS_DIR="$OUT_DIR/npm-packages"
BASE_PKG_DIR="$OUT_DIR/npm-base"
PACKS_DIR="$OUT_DIR/packs"
SMOKE_DIR="$OUT_DIR/smoke"

echo "==> Building $BINARY_NAME ($TARGET) v$VERSION"
echo "==> Output: $OUT_DIR"
echo

mkdir -p "$ARTIFACTS_DIR" "$PLATFORM_PKGS_DIR" "$BASE_PKG_DIR" "$PACKS_DIR"
mkdir -p "$NPM_CACHE_DIR"
export npm_config_cache="$NPM_CACHE_DIR"

(
  cd "$ROOT_DIR"
  cargo build --release --target "$TARGET"
)

ARCHIVE_BASENAME="${BINARY_NAME}-${VERSION}-${TARGET}.tar.gz"
ARCHIVE_PATH="$ARTIFACTS_DIR/$ARCHIVE_BASENAME"

echo "==> Creating archive: $ARCHIVE_PATH"
tar czf "$ARCHIVE_PATH" -C "$ROOT_DIR/target/$TARGET/release" "$BINARY_NAME"

echo "==> Creating platform package: ${BINARY_NAME}-darwin-arm64"
ONLY_TARGET="$TARGET" bash "$ROOT_DIR/npm/publish/create-platform-packages.sh" "$ARTIFACTS_DIR" "$PLATFORM_PKGS_DIR" "$VERSION"

echo "==> Staging base package"
cp -R "$ROOT_DIR/npm/." "$BASE_PKG_DIR/"

echo "==> Updating base package version"
BASE_PACKAGE_DIR="$BASE_PKG_DIR" bash "$ROOT_DIR/npm/publish/update-base-package.sh" "$VERSION"

echo "==> Packing tarballs (npm pack)"
platform_tgz="$(
  cd "$PLATFORM_PKGS_DIR/${BINARY_NAME}-darwin-arm64"
  npm pack --silent
)"
mv "$PLATFORM_PKGS_DIR/${BINARY_NAME}-darwin-arm64/$platform_tgz" "$PACKS_DIR/"

base_tgz="$(
  cd "$BASE_PKG_DIR"
  npm pack --silent
)"
mv "$BASE_PKG_DIR/$base_tgz" "$PACKS_DIR/"

echo "==> Created:"
echo "  - $PACKS_DIR/$platform_tgz"
echo "  - $PACKS_DIR/$base_tgz"

if [[ "${SMOKE_TEST:-1}" == "1" ]]; then
  echo
  echo "==> Smoke test (local install from tarballs)"
  mkdir -p "$SMOKE_DIR"
  (
    cd "$SMOKE_DIR"
    npm init -y >/dev/null
    npm install --silent "$PACKS_DIR/$platform_tgz" "$PACKS_DIR/$base_tgz"
    npx --no-install acp-extension-codex --help >/dev/null
  )
  echo "   ✓ OK: npx acp-extension-codex --help"
fi

echo
echo "✅ Done. Artifacts are under: $OUT_DIR"
