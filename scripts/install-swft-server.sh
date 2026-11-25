#!/usr/bin/env bash
# One-command installer for a remote Swft server (Mac Mini / macOS arm64 or Linux arm64/x64).
#
# Usage:
#   ./scripts/install-swft-server.sh [--version <x.y.z>] [--home <dir>] [--bin-dir <dir>]
#                                    [--repo <owner/repo>] [--no-service]
#
# Environment:
#   SWFT_HOME               Swft data directory (default: ~/Library/Application Support/Swft on macOS,
#                           ~/.local/share/swft on Linux)
#   SWFT_GITHUB_TOKEN       Optional GitHub token for private repositories (falls back to GITHUB_TOKEN)
#   SWFT_INSTALL_BIN_DIR    Where to place the `t3` launcher script (default: ~/.local/bin)
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/install-swft-server.sh [options]

Options:
  --version <x.y.z>    Install a specific release version instead of the latest GitHub Release
  --home <dir>         Swft server home directory (overrides SWFT_HOME)
  --bin-dir <dir>      Directory for the `t3` command launcher (default: ~/.local/bin)
  --repo <owner/repo>  GitHub repository (default: gojimq/swft)
  --no-service         Extract runtime and install `t3` launcher without running `t3 service install`
  -h, --help           Show this help message
EOF
}

REPO="gojimq/swft"
VERSION=""
HOME_OVERRIDE=""
BIN_DIR="${SWFT_INSTALL_BIN_DIR:-$HOME/.local/bin}"
INSTALL_SERVICE=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --version)
      [[ $# -ge 2 ]] || { echo "Error: --version requires a value" >&2; exit 1; }
      VERSION="${2#v}"
      shift 2
      ;;
    --home)
      [[ $# -ge 2 ]] || { echo "Error: --home requires a directory" >&2; exit 1; }
      HOME_OVERRIDE="$2"
      shift 2
      ;;
    --bin-dir)
      [[ $# -ge 2 ]] || { echo "Error: --bin-dir requires a directory" >&2; exit 1; }
      BIN_DIR="$2"
      shift 2
      ;;
    --repo)
      [[ $# -ge 2 ]] || { echo "Error: --repo requires owner/repo" >&2; exit 1; }
      REPO="$2"
      shift 2
      ;;
    --no-service)
      INSTALL_SERVICE=false
      shift
      ;;
    *)
      echo "Error: unknown option '$1'" >&2
      usage >&2
      exit 1
      ;;
  esac
done

fail() {
  echo "install-swft-server: $1" >&2
  exit 1
}

command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v tar >/dev/null 2>&1 || fail "tar is required"

case "$(uname -s)" in
  Darwin) PLATFORM="darwin" ;;
  Linux) PLATFORM="linux" ;;
  *) fail "unsupported operating system: $(uname -s)" ;;
esac

case "$(uname -m)" in
  arm64|aarch64) ARCH="arm64" ;;
  x86_64|amd64) ARCH="x64" ;;
  *) fail "unsupported CPU architecture: $(uname -m)" ;;
esac

PLATFORM_KEY="${PLATFORM}-${ARCH}"
if [[ "$PLATFORM_KEY" == "darwin-x64" ]]; then
  fail "darwin-x64 is not supported for standalone server binaries (use Apple Silicon arm64 or Linux arm64/x64)"
fi

if command -v sha256sum >/dev/null 2>&1; then
  sha256_file() { sha256sum "$1" | awk '{print $1}'; }
elif command -v shasum >/dev/null 2>&1; then
  sha256_file() { shasum -a 256 "$1" | awk '{print $1}'; }
else
  fail "shasum or sha256sum is required"
fi

if [[ -n "$HOME_OVERRIDE" ]]; then
  SWFT_HOME_DIR="$HOME_OVERRIDE"
elif [[ -n "${SWFT_HOME:-}" ]]; then
  SWFT_HOME_DIR="$SWFT_HOME"
elif [[ "$PLATFORM" == "darwin" ]]; then
  SWFT_HOME_DIR="$HOME/Library/Application Support/Swft"
else
  SWFT_HOME_DIR="$HOME/.local/share/swft"
fi
SWFT_HOME_DIR="${SWFT_HOME_DIR%/}"
BIN_DIR="${BIN_DIR%/}"

TOKEN="${SWFT_GITHUB_TOKEN:-${GITHUB_TOKEN:-}}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/swft-server-install-XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

RELEASE_JSON="$WORK_DIR/release.json"
if [[ -n "$VERSION" ]]; then
  if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
    fail "invalid semver version '$VERSION'"
  fi
  RELEASE_API_URL="https://api.github.com/repos/${REPO}/releases/tags/v${VERSION}"
else
  RELEASE_API_URL="https://api.github.com/repos/${REPO}/releases/latest"
fi

echo "==> Querying ${RELEASE_API_URL}"
API_HEADERS=(
  -H "Accept: application/vnd.github+json"
  -H "X-GitHub-Api-Version: 2022-11-28"
  -H "User-Agent: swft-installer"
)
if [[ -n "$TOKEN" ]]; then
  API_HEADERS+=(-H "Authorization: Bearer ${TOKEN}")
fi

HTTP_STATUS="$(curl -sSL "${API_HEADERS[@]}" -w '%{http_code}' "$RELEASE_API_URL" -o "$RELEASE_JSON")"
if [[ "$HTTP_STATUS" == "404" ]]; then
  if [[ -z "$TOKEN" ]]; then
    fail "GitHub release not found (HTTP 404). If ${REPO} is private, export SWFT_GITHUB_TOKEN (or GITHUB_TOKEN) and retry."
  else
    fail "GitHub release not found at ${RELEASE_API_URL} (HTTP 404)."
  fi
elif [[ "$HTTP_STATUS" -lt 200 || "$HTTP_STATUS" -ge 300 ]]; then
  fail "GitHub API request failed with HTTP ${HTTP_STATUS}."
fi

extract_tag_name() {
  if command -v jq >/dev/null 2>&1; then
    jq -r '.tag_name // empty' "$RELEASE_JSON"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get("tag_name", ""))' "$RELEASE_JSON"
  else
    sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$RELEASE_JSON" | head -n 1
  fi
}

extract_asset_api_url() {
  local asset_name="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg name "$asset_name" '.assets[] | select(.name == $name) | .url' "$RELEASE_JSON" | head -n 1
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c '
import json, sys
data = json.load(open(sys.argv[1]))
name = sys.argv[2]
for asset in data.get("assets", []):
    if asset.get("name") == name:
        print(asset.get("url", ""))
        break
' "$RELEASE_JSON" "$asset_name"
  else
    fail "jq or python3 is required to resolve private GitHub Release asset URLs."
  fi
}

if [[ -z "$VERSION" ]]; then
  TAG_NAME="$(extract_tag_name)"
  VERSION="${TAG_NAME#v}"
  [[ -n "$VERSION" ]] || fail "could not determine release version from ${RELEASE_API_URL}"
fi

ARCHIVE_NAME="t3-${VERSION}-${PLATFORM_KEY}.tar.gz"
echo "==> Installing Swft server v${VERSION} (${PLATFORM_KEY}) into ${SWFT_HOME_DIR}"

download_release_asset() {
  local asset_name="$1"
  local dest_path="$2"
  if [[ -n "$TOKEN" ]]; then
    local asset_api_url
    asset_api_url="$(extract_asset_api_url "$asset_name")"
    [[ -n "$asset_api_url" ]] || fail "asset '${asset_name}' was not found in release v${VERSION}"

    # Two-step redirect so the GitHub Bearer token is never sent to S3.
    local headers_file="$WORK_DIR/headers-${asset_name}.txt"
    local step1_status
    step1_status="$(curl -sS -D "$headers_file" -o "$dest_path" -w '%{http_code}' \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Accept: application/octet-stream" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      -H "User-Agent: swft-installer" \
      "$asset_api_url")"

    case "$step1_status" in
      301|302|303|307|308)
        local signed_url
        signed_url="$(awk 'tolower($1) == "location:" { sub(/\r$/, "", $2); print $2; exit }' "$headers_file")"
        [[ -n "$signed_url" ]] || fail "missing redirect Location header for ${asset_name}"
        curl -fsSL "$signed_url" -o "$dest_path" || fail "failed downloading ${asset_name} from signed URL"
        ;;
      2??)
        ;;
      *)
        fail "failed fetching asset ${asset_name} (HTTP ${step1_status})"
        ;;
    esac
  else
    local direct_url="https://github.com/${REPO}/releases/download/v${VERSION}/${asset_name}"
    curl -fsSL "$direct_url" -o "$dest_path" || fail "failed downloading ${direct_url}"
  fi
}

CHECKSUMS_PATH="$WORK_DIR/SHA256SUMS"
ARCHIVE_PATH="$WORK_DIR/$ARCHIVE_NAME"

echo "==> Downloading SHA256SUMS"
download_release_asset "SHA256SUMS" "$CHECKSUMS_PATH"

EXPECTED_SHA="$(awk -v name="$ARCHIVE_NAME" '
  {
    file = $2
    sub(/^\*/, "", file)
    if (file == name) {
      print tolower($1)
      exit
    }
  }
' "$CHECKSUMS_PATH")"
[[ -n "$EXPECTED_SHA" ]] || fail "${ARCHIVE_NAME} was not found in SHA256SUMS"

echo "==> Downloading ${ARCHIVE_NAME}"
download_release_asset "$ARCHIVE_NAME" "$ARCHIVE_PATH"

echo "==> Verifying SHA-256 checksum"
ACTUAL_SHA="$(sha256_file "$ARCHIVE_PATH" | tr '[:upper:]' '[:lower:]')"
if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then
  fail "checksum mismatch for ${ARCHIVE_NAME} (expected ${EXPECTED_SHA}, got ${ACTUAL_SHA})"
fi

VERSIONS_DIR="${SWFT_HOME_DIR}/runtime/versions"
TARGET_DIR="${VERSIONS_DIR}/${VERSION}"
mkdir -p "$VERSIONS_DIR"

STAGING_DIR="$(mktemp -d "${VERSIONS_DIR}/.staging-XXXXXX")"
cleanup_all() {
  rm -rf "$WORK_DIR" "$STAGING_DIR"
}
trap cleanup_all EXIT

echo "==> Extracting runtime to ${TARGET_DIR}"
tar -xzf "$ARCHIVE_PATH" -C "$STAGING_DIR" --strip-components=1
chmod +x "${STAGING_DIR}/t3"
"${STAGING_DIR}/t3" --version >/dev/null || fail "extracted t3 binary failed smoke check (--version)"
printf '%s\n' "$VERSION" > "${STAGING_DIR}/.install-complete"

rm -rf "$TARGET_DIR"
mv "$STAGING_DIR" "$TARGET_DIR"

echo "==> Installing launcher at ${BIN_DIR}/t3"
mkdir -p "$BIN_DIR"
LAUNCHER_PATH="${BIN_DIR}/t3"
ESCAPED_EXEC="${TARGET_DIR}/t3"
ESCAPED_EXEC="${ESCAPED_EXEC//\'/\'\\\'\'}"
cat > "$LAUNCHER_PATH" <<EOF
#!/bin/sh
exec '${ESCAPED_EXEC}' "\$@"
EOF
chmod 755 "$LAUNCHER_PATH"

LAUNCHERS_FILE="${SWFT_HOME_DIR}/runtime/launchers"
grep -qxF "$LAUNCHER_PATH" "$LAUNCHERS_FILE" 2>/dev/null || printf '%s\n' "$LAUNCHER_PATH" >> "$LAUNCHERS_FILE"

if [[ -n "$TOKEN" ]]; then
  SERVICE_ENV_FILE="${SWFT_HOME_DIR}/service.env"
  if [[ ! -f "$SERVICE_ENV_FILE" ]] || ! grep -q '^SWFT_GITHUB_TOKEN=' "$SERVICE_ENV_FILE"; then
    (
      umask 077
      printf 'SWFT_GITHUB_TOKEN=%s\n' "$TOKEN" >> "$SERVICE_ENV_FILE"
    )
    chmod 600 "$SERVICE_ENV_FILE"
  fi
fi

if [[ "$INSTALL_SERVICE" == true ]]; then
  echo "==> Installing background service via t3 service install"
  T3CODE_HOME="$SWFT_HOME_DIR" \
  T3CODE_INSTALL_BIN_DIR="$BIN_DIR" \
  SWFT_GITHUB_TOKEN="${TOKEN}" \
    "${TARGET_DIR}/t3" service install --base-dir "$SWFT_HOME_DIR"
fi

echo ""
echo "Swft server v${VERSION} installed successfully!"
echo "  Home:     ${SWFT_HOME_DIR}"
echo "  Runtime:  ${TARGET_DIR}/t3"
echo "  Launcher: ${LAUNCHER_PATH}"
echo ""
echo "Next steps:"
echo "  1. Pair this server with Swft on your MacBook Pro:"
echo "     \"${LAUNCHER_PATH}\" pair --base-dir \"${SWFT_HOME_DIR}\""
echo "  2. Check service status anytime:"
echo "     \"${LAUNCHER_PATH}\" service status --base-dir \"${SWFT_HOME_DIR}\""
