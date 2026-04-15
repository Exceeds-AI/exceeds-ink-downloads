#!/bin/sh
set -eu

# Public Exceeds collector (Vercel). Override both OTLP + compat together if you use a different host.
DEFAULT_OTLP_HTTP="https://exceeds-ink.vercel.app/api/v1/otlp"
DEFAULT_COMPAT="https://exceeds-ink.vercel.app/api/v1/ingest"

REPO="${EXCEEDS_INK_REPO:-Exceeds-AI/exceeds-ink-downloads}"
INSTALL_DIR="${EXCEEDS_INK_INSTALL_DIR:-$HOME/.exceeds-ink/bin}"
VERSION="${EXCEEDS_INK_VERSION:-latest}"
DOWNLOAD_BASE="${EXCEEDS_INK_DOWNLOAD_BASE_URL:-}"
COMPAT_ENDPOINT="${EXCEEDS_INK_COMPAT_ENDPOINT:-}"
OTLP_HTTP_ENDPOINT="${EXCEEDS_INK_OTLP_HTTP_ENDPOINT:-}"
OTLP_GRPC_ENDPOINT="${EXCEEDS_INK_OTLP_GRPC_ENDPOINT:-}"
API_KEY="${EXCEEDS_INK_API_KEY:-}"
BINARY_ONLY=0

usage() {
  cat <<'EOF'
Usage: curl -fsSL https://raw.githubusercontent.com/Exceeds-AI/exceeds-ink-downloads/main/install.sh | sh

By default this installs the binary, runs `exceeds-ink setup`, then `exceeds-ink install --all` against the
public Exceeds Vercel collector. Afterward run `exceeds-ink init` in each git repo you want to track.

Optional flags:
  --version <version>             Install a specific version (for example: 0.1.0)
  --install-dir <path>            Override the binary install directory
  --download-base <url>           Override the public asset base URL
  --repo <owner/name>             Override the GitHub repository used for releases
  --binary-only                   Only download and install the binary (skip setup / install --all)
  --compat-endpoint <url>         Override compat ingest (requires --otlp-http-endpoint too)
  --otlp-http-endpoint <url>      Override OTLP HTTP (requires --compat-endpoint too)
  --otlp-grpc-endpoint <url>      Optional; passed through when set
  --api-key <key>                 Optional; passed to setup and install when set
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
    --binary-only)
      BINARY_ONLY=1
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

case "$(printf '%s' "${EXCEEDS_INK_BINARY_ONLY:-}" | tr '[:upper:]' '[:lower:]')" in
  1|true|yes|on) BINARY_ONLY=1 ;;
esac

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
      echo "Set EXCEEDS_INK_VERSION or publish ${DOWNLOAD_BASE%/}/LATEST." >&2
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

resolve_effective_endpoints() {
  if [ -n "$OTLP_HTTP_ENDPOINT" ] && [ -n "$COMPAT_ENDPOINT" ]; then
    EFF_OTLP_HTTP="$OTLP_HTTP_ENDPOINT"
    EFF_COMPAT="$COMPAT_ENDPOINT"
    return
  fi
  if [ -z "$OTLP_HTTP_ENDPOINT" ] && [ -z "$COMPAT_ENDPOINT" ]; then
    EFF_OTLP_HTTP="$DEFAULT_OTLP_HTTP"
    EFF_COMPAT="$DEFAULT_COMPAT"
    return
  fi
  echo "Set both EXCEEDS_INK_OTLP_HTTP_ENDPOINT and EXCEEDS_INK_COMPAT_ENDPOINT to override the collector, or set neither to use the default Exceeds Vercel URLs." >&2
  exit 1
}

run_setup_and_install() {
  install_path="$1"
  resolve_effective_endpoints

  echo "Running exceeds-ink setup (collector: Exceeds Vercel or your overrides)..."
  set -- "$install_path" setup \
    --otlp-http-endpoint "$EFF_OTLP_HTTP" \
    --compat-endpoint "$EFF_COMPAT"
  if [ -n "$OTLP_GRPC_ENDPOINT" ]; then
    set -- "$@" --otlp-grpc-endpoint "$OTLP_GRPC_ENDPOINT"
  fi
  if [ -n "$API_KEY" ]; then
    set -- "$@" --api-key "$API_KEY"
  fi
  "$@"

  echo "Running exceeds-ink install --all..."
  set -- "$install_path" install --all \
    --otlp-http-endpoint "$EFF_OTLP_HTTP" \
    --compat-endpoint "$EFF_COMPAT"
  if [ -n "$OTLP_GRPC_ENDPOINT" ]; then
    set -- "$@" --otlp-grpc-endpoint "$OTLP_GRPC_ENDPOINT"
  fi
  if [ -n "$API_KEY" ]; then
    set -- "$@" --api-key "$API_KEY"
  fi
  "$@"
}

need_cmd curl
need_cmd tar
need_cmd mktemp
need_cmd awk

TARGET="$(detect_target)"
RESOLVED_VERSION="$(resolve_version)"
ASSET="exceeds-ink_${RESOLVED_VERSION}_${TARGET}.tar.gz"
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
install_path="$INSTALL_DIR/exceeds-ink"
cp "$TMP_DIR/exceeds-ink" "$install_path"
chmod 755 "$install_path"

echo "Installed exceeds-ink to $install_path"

if [ "$BINARY_ONLY" != "1" ]; then
  run_setup_and_install "$install_path"
fi

case ":$PATH:" in
  *":$INSTALL_DIR:"*)
    ;;
  *)
    echo
    echo "Add exceeds-ink to your PATH:"
    echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
    ;;
esac

echo
echo "Next steps:"
echo "  1. Run 'exceeds-ink --version' to confirm the install."
if [ "$BINARY_ONLY" = "1" ]; then
  echo "  2. Run 'exceeds-ink setup' / 'exceeds-ink install' as needed, or re-run this installer without --binary-only."
  echo "  3. Run 'exceeds-ink init' inside each repo you want to track."
else
  echo "  2. Run 'exceeds-ink init' inside each repo you want to track."
fi
