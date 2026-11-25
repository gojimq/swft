#!/usr/bin/env bash
# Build and optionally publish a macOS arm64 Swft release (standalone Swft.app + t3 server archive + SHA256SUMS).
#
# Usage:
#   ./scripts/release-swft.sh <version> [--dry-run] [--allow-dirty] [--notes "..."] [--notes-file <path>]
#                             [--repo <owner/repo>] [--output-dir <dir>] [--sign-identity <identity>]
#
# Working-tree behavior:
#   - Normal release: stamps <version> into apps/macos/Resources/Info.plist (CFBundleShortVersionString)
#     and apps/server/package.json (version), builds artifacts into --output-dir (default: release-swft/<version>),
#     and creates GitHub Release v<version> via `gh release create`.
#   - --dry-run: temporarily stamps <version> for the build so embedded version metadata matches <version>,
#     restores apps/macos/Resources/Info.plist and apps/server/package.json on exit, writes all artifacts
#     and SHA256SUMS to --output-dir, and skips `gh release create`.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/release-swft.sh <version> [options]

Arguments:
  <version>                   Exact semver version without leading 'v' (e.g. 0.2.0 or 0.2.0-beta.1)

Options:
  --dry-run                   Build and verify all artifacts locally; restore version files and skip publishing
  --allow-dirty               Allow running with uncommitted git changes
  --notes <text>              Release notes text passed to `gh release create`
  --notes-file <path>         Release notes file passed to `gh release create`
  --repo <owner/repo>         GitHub repository (default: gojimq/swft)
  --output-dir <dir>          Directory for staged release assets (default: release-swft/<version>)
  --sign-identity <identity>  Codesign identity (default: $SWFT_MAC_SIGN_IDENTITY or '-' for ad-hoc)
  -h, --help                  Show this help message
EOF
}

if [[ $# -eq 0 ]]; then
  usage >&2
  exit 1
fi

VERSION=""
DRY_RUN=false
ALLOW_DIRTY=false
NOTES=""
NOTES_FILE=""
REPO="gojimq/swft"
OUTPUT_DIR=""
SIGN_IDENTITY="${SWFT_MAC_SIGN_IDENTITY:-${T3CODE_CLI_MAC_SIGN_IDENTITY:--}}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --allow-dirty)
      ALLOW_DIRTY=true
      shift
      ;;
    --notes)
      [[ $# -ge 2 ]] || { echo "Error: --notes requires a value" >&2; exit 1; }
      NOTES="$2"
      shift 2
      ;;
    --notes-file)
      [[ $# -ge 2 ]] || { echo "Error: --notes-file requires a path" >&2; exit 1; }
      NOTES_FILE="$2"
      shift 2
      ;;
    --repo)
      [[ $# -ge 2 ]] || { echo "Error: --repo requires a value" >&2; exit 1; }
      REPO="$2"
      shift 2
      ;;
    --output-dir)
      [[ $# -ge 2 ]] || { echo "Error: --output-dir requires a path" >&2; exit 1; }
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --sign-identity)
      [[ $# -ge 2 ]] || { echo "Error: --sign-identity requires a value" >&2; exit 1; }
      SIGN_IDENTITY="$2"
      shift 2
      ;;
    -*)
      echo "Error: unknown option '$1'" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -z "$VERSION" ]]; then
        VERSION="$1"
        shift
      else
        echo "Error: unexpected positional argument '$1'" >&2
        usage >&2
        exit 1
      fi
      ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  echo "Error: missing required <version> argument" >&2
  usage >&2
  exit 1
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  echo "Error: '$VERSION' is not a valid semver version (expected e.g. 0.2.0 or 0.2.0-beta.1 without leading 'v')." >&2
  exit 1
fi

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  echo "Error: release-swft.sh must be run on macOS arm64 (detected $(uname -s)/$(uname -m))." >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [[ "$DRY_RUN" == false && "$ALLOW_DIRTY" == false ]]; then
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "Error: git working tree is dirty. Commit or stash changes, or pass --allow-dirty / --dry-run." >&2
    exit 1
  fi
fi

if [[ "$DRY_RUN" == false ]]; then
  command -v gh >/dev/null 2>&1 || { echo "Error: GitHub CLI (gh) is required to publish releases." >&2; exit 1; }
fi

command -v node >/dev/null 2>&1 || { echo "Error: node is required." >&2; exit 1; }
command -v swift >/dev/null 2>&1 || { echo "Error: swift is required." >&2; exit 1; }
command -v ditto >/dev/null 2>&1 || { echo "Error: ditto is required." >&2; exit 1; }
command -v shasum >/dev/null 2>&1 || { echo "Error: shasum is required." >&2; exit 1; }

if [[ -x "$REPO_ROOT/node_modules/.bin/vp" ]]; then
  export PATH="$REPO_ROOT/node_modules/.bin:$PATH"
  VP_BIN="$REPO_ROOT/node_modules/.bin/vp"
elif command -v vp >/dev/null 2>&1; then
  VP_BIN="$(command -v vp)"
else
  echo "Error: vite-plus (vp) not found in node_modules/.bin or PATH." >&2
  exit 1
fi

STAGE_DIR="${OUTPUT_DIR:-$REPO_ROOT/release-swft/$VERSION}"
mkdir -p "$STAGE_DIR"
STAGE_DIR="$(cd "$STAGE_DIR" && pwd)"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/swft-release-${VERSION}-XXXXXX")"
INFO_PLIST="$REPO_ROOT/apps/macos/Resources/Info.plist"
SERVER_PKG="$REPO_ROOT/apps/server/package.json"
BACKUP_PLIST="$WORK_DIR/Info.plist.orig"
BACKUP_PKG="$WORK_DIR/package.json.orig"
cp "$INFO_PLIST" "$BACKUP_PLIST"
cp "$SERVER_PKG" "$BACKUP_PKG"

cleanup() {
  if [[ "$DRY_RUN" == true ]]; then
    cp "$BACKUP_PLIST" "$INFO_PLIST"
    cp "$BACKUP_PKG" "$SERVER_PKG"
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

echo "==> Stamping version ${VERSION} into Info.plist and apps/server/package.json"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$INFO_PLIST"
node -e '
  const fs = require("node:fs");
  const file = process.argv[1];
  const version = process.argv[2];
  const raw = fs.readFileSync(file, "utf8");
  const pkg = JSON.parse(raw);
  pkg.version = version;
  fs.writeFileSync(file, JSON.stringify(pkg, null, 2) + "\n");
' "$SERVER_PKG" "$VERSION"

echo "==> Building web client and server bundle"
"$VP_BIN" run --filter @t3tools/web build
node "$REPO_ROOT/apps/server/scripts/cli.ts" build

echo "==> Staging native resource monitor"
RESOURCE_MONITOR_STAGE="$WORK_DIR/resource-monitor"
mkdir -p "$RESOURCE_MONITOR_STAGE/darwin-arm64"
if [[ -f "$REPO_ROOT/apps/server/dist/resource-monitor/darwin-arm64/t3-resource-monitor" ]]; then
  cp "$REPO_ROOT/apps/server/dist/resource-monitor/darwin-arm64/t3-resource-monitor" \
    "$RESOURCE_MONITOR_STAGE/darwin-arm64/t3-resource-monitor"
else
  command -v cargo >/dev/null 2>&1 || { echo "Error: cargo is required to build native/resource-monitor." >&2; exit 1; }
  cargo build --locked --release --manifest-path "$REPO_ROOT/native/resource-monitor/Cargo.toml"
  cp "$REPO_ROOT/native/resource-monitor/target/release/t3-resource-monitor" \
    "$RESOURCE_MONITOR_STAGE/darwin-arm64/t3-resource-monitor"
fi

echo "==> Building server single-executable (SEA)"
node "$REPO_ROOT/apps/server/scripts/cli.ts" build-exe --target darwin-arm64

SERVER_ARCHIVE_NAME="t3-${VERSION}-darwin-arm64.tar.gz"
APP_ARCHIVE_NAME="Swft-${VERSION}-darwin-arm64.zip"

echo "==> Packaging ${SERVER_ARCHIVE_NAME}"
T3CODE_CLI_MAC_SIGN_IDENTITY="$SIGN_IDENTITY" \
  node "$REPO_ROOT/scripts/build-cli-archive.ts" \
    --platform mac \
    --arch arm64 \
    --version "$VERSION" \
    --resource-monitor-dir "$RESOURCE_MONITOR_STAGE" \
    --output-dir "$STAGE_DIR"

SERVER_ARCHIVE_PATH="$STAGE_DIR/$SERVER_ARCHIVE_NAME"
[[ -f "$SERVER_ARCHIVE_PATH" ]] || { echo "Error: expected $SERVER_ARCHIVE_PATH was not created." >&2; exit 1; }

echo "==> Building release Swft.app"
"$REPO_ROOT/apps/macos/scripts/bundle.sh" release

APP_BUNDLE="$REPO_ROOT/apps/macos/build/Swft.app"
EMBEDDED_SERVER_DIR="$APP_BUNDLE/Contents/Resources/server"

echo "==> Embedding standalone server runtime into Swft.app/Contents/Resources/server/"
rm -rf "$EMBEDDED_SERVER_DIR"
mkdir -p "$EMBEDDED_SERVER_DIR"
tar -xzf "$SERVER_ARCHIVE_PATH" -C "$EMBEDDED_SERVER_DIR" --strip-components=1
chmod +x "$EMBEDDED_SERVER_DIR/t3"
"$EMBEDDED_SERVER_DIR/t3" --version

echo "==> Signing Swft.app with identity '${SIGN_IDENTITY}'"
SIGN_ARGS=(--force --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  SIGN_ARGS+=(--options runtime --timestamp)
fi
codesign "${SIGN_ARGS[@]}" "$APP_BUNDLE/Contents/MacOS/Swft"
codesign "${SIGN_ARGS[@]}" "$APP_BUNDLE"

APP_ARCHIVE_PATH="$STAGE_DIR/$APP_ARCHIVE_NAME"
echo "==> Archiving ${APP_ARCHIVE_NAME}"
rm -f "$APP_ARCHIVE_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$APP_ARCHIVE_PATH"

echo "==> Generating SHA256SUMS"
(
  cd "$STAGE_DIR"
  shasum -a 256 "$SERVER_ARCHIVE_NAME" "$APP_ARCHIVE_NAME" > SHA256SUMS
)
cat "$STAGE_DIR/SHA256SUMS"

if [[ "$DRY_RUN" == true ]]; then
  echo ""
  echo "Dry run complete. Staged artifacts in: $STAGE_DIR"
  echo "Version files restored to original working-tree contents."
  exit 0
fi

TAG="v${VERSION}"
echo "==> Publishing GitHub Release ${TAG} to ${REPO}"
GH_ARGS=(release create "$TAG" --repo "$REPO" --title "Swft ${TAG}")
if [[ -n "$NOTES_FILE" ]]; then
  GH_ARGS+=(--notes-file "$NOTES_FILE")
elif [[ -n "$NOTES" ]]; then
  GH_ARGS+=(--notes "$NOTES")
else
  GH_ARGS+=(--generate-notes)
fi

gh "${GH_ARGS[@]}" \
  "$SERVER_ARCHIVE_PATH" \
  "$APP_ARCHIVE_PATH" \
  "$STAGE_DIR/SHA256SUMS"

echo "==> Published Swft ${TAG} to https://github.com/${REPO}/releases/tag/${TAG}"
