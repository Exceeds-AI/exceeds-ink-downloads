#!/bin/sh
set -eu

REPO="${AI_INK_REPO:-Exceeds-AI/exceeds-ink-downloads}"
INSTALL_DIR="${AI_INK_INSTALL_DIR:-$HOME/.ai-ink/bin}"
VERSION="${AI_INK_VERSION:-latest}"
# Optional public asset base URL, e.g. https://downloads.example.com/ai-ink.
# Assets are expected under ${AI_INK_DOWNLOAD_BASE_URL}/v${VERSION}/.
DOWNLOAD_BASE="${AI_INK_DOWNLOAD_BASE_URL:-}"
INSTALL_INTEGRATIONS="${AI_INK_INSTALL_INTEGRATIONS:-0}"
COMPAT_ENDPOINT="${AI_INK_COMPAT_ENDPOINT:-}"
OTLP_HTTP_ENDPOINT="${AI_INK_OTLP_HTTP_ENDPOINT:-}"
OTLP_GRPC_ENDPOINT="${AI_INK_OTLP_GRPC_ENDPOINT:-}"
API_KEY="${AI_INK_API_KEY:-}"

usage() {
  cat <<'EOF'
Usage: curl -fsSL https://raw.githubusercontent.com/Exceeds-AI/exceeds-ink-downloads/main/install.sh | sh

Optional flags:
  --version <version>             Install a specific version (for example: 0.1.0)
  --install-dir <path>            Override the binary install directory
  --download-base <url>           Override the public asset base URL
  --repo <owner/name>             Override the GitHub repository used for releases
  --install-integrations          Run `ai-ink install --all` after installing the binary
  --compat-endpoint <url>         Pass through to `ai-ink install --all`
  --otlp-http-endpoint <url>      Pass through to `ai-ink install --all`
  --otlp-grpc-endpoint <url>      Pass through to `ai-ink install --all`
  --api-key <key>                 Pass through to `ai-ink install --all`
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --install-dir)
      INSTALL_DIR="$2"
      shift 2
      ;;
    --download-base)
      DOWNLOAD_BASE="$2"
      shift 2
      ;;
    --repo)
      REPO="$2"
      shift 2
      ;;
    --install-integrations)
      INSTALL_INTEGRATIONS=1
      shift 1
      ;;
    --compat-endpoint)
      COMPAT_ENDPOINT="$2"
      shift 2
      ;;
    --otlp-http-endpoint)
      OTLP_HTTP_ENDPOINT="$2"
      shift 2
      ;;
    --otlp-grpc-endpoint)
      OTLP_GRPC_ENDPOINT="$2"
      shift 2
      ;;
    --api-key)
      API_KEY="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 1
  fi
}

resolve_version() {
  if [ "$VERSION" != "latest" ]; then
    printf '%s' "${VERSION#v}"
    return
  fi

  if [ -n "$DOWNLOAD_BASE" ]; then
    latest_url="${DOWNLOAD_BASE%/}/LATEST"
    latest_version="$(curl -fsSL "$latest_url" 2>/dev/null | tr -d '\r' | awk 'NF { print; exit }' || true)"
    latest_version="${latest_version#v}"
    if [ -n "$latest_version" ]; then
      printf '%s' "$latest_version"
      return
    fi
  fi

  latest_json="$(curl -fsSL -H 'Accept: application/vnd.github+json' "https://api.github.com/repos/$REPO/releases/latest")"
  latest_version="$(printf '%s\n' "$latest_json" | awk -F'"' '/"tag_name":/ { sub(/^v/, "", $4); print $4; exit }')"
  if [ -z "$latest_version" ]; then
    echo "Failed to resolve latest release for $REPO" >&2
    if [ -n "$DOWNLOAD_BASE" ]; then
      echo "Set AI_INK_VERSION or publish ${DOWNLOAD_BASE%/}/LATEST." >&2
    fi
    exit 1
  fi
  printf '%s' "$latest_version"
}

detect_target() {
  os="$(uname -s)"
  arch="$(uname -m)"

  case "$os" in
    Darwin) os_part="apple-darwin" ;;
    Linux) os_part="unknown-linux-gnu" ;;
    *)
      echo "Unsupported OS for install.sh: $os" >&2
      echo "Use the PowerShell installer on Windows." >&2
      exit 1
      ;;
  esac

  case "$arch" in
    x86_64|amd64) arch_part="x86_64" ;;
    arm64|aarch64) arch_part="aarch64" ;;
    *)
      echo "Unsupported architecture: $arch" >&2
      exit 1
      ;;
  esac

  printf '%s-%s' "$arch_part" "$os_part"
}

verify_checksum() {
  file="$1"
  checksum_file="$2"

  expected="$(awk '{print $1}' "$checksum_file")"
  if [ -z "$expected" ]; then
    echo "Checksum file is empty: $checksum_file" >&2
    exit 1
  fi

  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$file" | awk '{print $1}')"
  else
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  fi

  if [ "$expected" != "$actual" ]; then
    echo "Checksum verification failed for $file" >&2
    exit 1
  fi
}

need_cmd curl
need_cmd tar
need_cmd mktemp
need_cmd awk

TARGET="$(detect_target)"
RESOLVED_VERSION="$(resolve_version)"
ASSET="ai-ink_${RESOLVED_VERSION}_${TARGET}.tar.gz"
if [ -n "$DOWNLOAD_BASE" ]; then
  BASE_URL="${DOWNLOAD_BASE%/}/v${RESOLVED_VERSION}"
else
  BASE_URL="https://github.com/${REPO}/releases/download/v${RESOLVED_VERSION}"
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

ARCHIVE_PATH="$TMP_DIR/$ASSET"
CHECKSUM_PATH="$TMP_DIR/$ASSET.sha256"

if [ -n "$DOWNLOAD_BASE" ]; then
  echo "Downloading ${ASSET} from ${BASE_URL}..."
else
  echo "Downloading ${ASSET} from ${REPO}..."
fi
curl -fsSL "$BASE_URL/$ASSET" -o "$ARCHIVE_PATH"
curl -fsSL "$BASE_URL/$ASSET.sha256" -o "$CHECKSUM_PATH"
verify_checksum "$ARCHIVE_PATH" "$CHECKSUM_PATH"

mkdir -p "$INSTALL_DIR"
tar -xzf "$ARCHIVE_PATH" -C "$TMP_DIR"
install_path="$INSTALL_DIR/ai-ink"
cp "$TMP_DIR/ai-ink" "$install_path"
chmod 755 "$install_path"

echo "Installed ai-ink to $install_path"

if [ "$INSTALL_INTEGRATIONS" = "1" ]; then
  set -- install --all
  if [ -n "$COMPAT_ENDPOINT" ]; then
    set -- "$@" --compat-endpoint "$COMPAT_ENDPOINT"
  fi
  if [ -n "$OTLP_HTTP_ENDPOINT" ]; then
    set -- "$@" --otlp-http-endpoint "$OTLP_HTTP_ENDPOINT"
  fi
  if [ -n "$OTLP_GRPC_ENDPOINT" ]; then
    set -- "$@" --otlp-grpc-endpoint "$OTLP_GRPC_ENDPOINT"
  fi
  if [ -n "$API_KEY" ]; then
    set -- "$@" --api-key "$API_KEY"
  fi
  "$install_path" "$@"
fi

case ":$PATH:" in
  *":$INSTALL_DIR:"*)
    ;;
  *)
    echo
    echo "Add ai-ink to your PATH:"
    echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
    ;;
esac

echo
echo "Next steps:"
echo "  1. Run 'ai-ink --version' to confirm the install."
echo "  2. Run 'ai-ink init' inside each repo you want to track."
