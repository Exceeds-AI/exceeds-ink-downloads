#!/bin/sh
set -eu

# Public Exceeds collector (Vercel). Override both OTLP + compat together if you use a different host.
DEFAULT_OTLP_HTTP="https://exceeds-ink.vercel.app/api/v1/otlp"
DEFAULT_COMPAT="https://exceeds-ink.vercel.app/api/v1/ingest"
RELEASE_MANIFEST_NAME="release-manifest.json"
RELEASE_MANIFEST_SIG_NAME="release-manifest.rsa.sig"

REPO="${EXCEEDS_INK_REPO:-Exceeds-AI/exceeds-ink-downloads}"
INSTALL_DIR="${EXCEEDS_INK_INSTALL_DIR:-$HOME/.exceeds-ink/bin}"
VERSION="${EXCEEDS_INK_VERSION:-latest}"
DOWNLOAD_BASE="${EXCEEDS_INK_DOWNLOAD_BASE_URL:-}"
COMPAT_ENDPOINT="${EXCEEDS_INK_COMPAT_ENDPOINT:-}"
OTLP_HTTP_ENDPOINT="${EXCEEDS_INK_OTLP_HTTP_ENDPOINT:-}"
OTLP_GRPC_ENDPOINT="${EXCEEDS_INK_OTLP_GRPC_ENDPOINT:-}"
API_KEY="${EXCEEDS_INK_API_KEY:-}"
INSTALLER_REGISTRATION_TIMEOUT_SECONDS="${EXCEEDS_INK_INSTALLER_REGISTRATION_TIMEOUT_SECONDS:-600}"
INSTALLER_REGISTRATION_POLL_SECONDS="${EXCEEDS_INK_INSTALLER_REGISTRATION_POLL_SECONDS:-5}"
ENDPOINT_TRUST_FLAG=""
BINARY_ONLY=0

release_public_key_pem() {
  if [ -n "${EXCEEDS_INK_RELEASE_PUBLIC_KEY_PEM:-}" ]; then
    printf '%s\n' "$EXCEEDS_INK_RELEASE_PUBLIC_KEY_PEM"
    return
  fi
  cat <<'EOF'
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAlnPeY/YmSu1zHZTUTKyD
v7xVo+7OfHHjHtmphaRtrzbX+lESyXhgEKGaqbPXiSlwq52OqAME7HN5aouMJ5yB
PYXU4lHZw9ufprvo8zsOZXFW/ajFI1kP8sbsU5ZjByM2iNikO7urYzETaKWaFAMh
thsK7ie1+mkCe+9s8ZNiFi2B/x0oRYIUylOY18/WAp8gv5ilJPCUlL2amjkuso5t
B0JVlFOIe6aka4agJVyss5MW0UqKRdv2q53vbw/537xYcJmB1fVAj6NhN8ALY9Dj
oinfdbjpS3lDeIRxXTjGcB96HacTUmZvPfcXyoSiqjVatz9pCTRG7zwsmLapl4lC
FQIDAQAB
-----END PUBLIC KEY-----
EOF
}

usage() {
  cat <<'EOF'
Usage: curl -fsSL https://raw.githubusercontent.com/Exceeds-AI/exceeds-ink-downloads/main/install.sh | sh

By default this installs the binary, clears any existing local machine registration state, runs
`exceeds-ink setup`, completes machine registration, then `exceeds-ink install --all` against the
public Exceeds Vercel collector. Rerunning the installer intentionally re-pairs the machine.
Afterward run `exceeds-ink init` in each git repo you want to track.

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
  --official-endpoint             Explicitly use the built-in public Exceeds endpoint
  --dev-endpoint                  Allow localhost/dev endpoint overrides
  --allow-custom-endpoint         Allow arbitrary custom endpoint overrides
EOF
}

set_endpoint_trust_flag() {
  flag="$1"
  if [ -n "$ENDPOINT_TRUST_FLAG" ] && [ "$ENDPOINT_TRUST_FLAG" != "$flag" ]; then
    echo "Choose at most one of --official-endpoint, --dev-endpoint, or --allow-custom-endpoint." >&2
    exit 1
  fi
  ENDPOINT_TRUST_FLAG="$flag"
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
    --official-endpoint)
      set_endpoint_trust_flag "--official-endpoint"
      shift 1
      ;;
    --dev-endpoint)
      set_endpoint_trust_flag "--dev-endpoint"
      shift 1
      ;;
    --allow-custom-endpoint)
      set_endpoint_trust_flag "--allow-custom-endpoint"
      shift 1
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

manifest_asset_sha256() {
  manifest_file="$1"
  asset_name="$2"
  version="$3"

  tr -d '\r\n\t ' < "$manifest_file" | awk -v asset="$asset_name" -v version="$version" '
    {
      version_needle = "\"version\":\"" version "\""
      if (index($0, version_needle) == 0) {
        print "release is not trusted: manifest version mismatch" > "/dev/stderr"
        exit 2
      }
      asset_needle = "\"name\":\"" asset "\""
      start = index($0, asset_needle)
      if (start == 0) {
        print "release is not trusted: manifest missing asset " asset > "/dev/stderr"
        exit 3
      }
      rest = substr($0, start)
      split(rest, parts, "\"sha256\":\"")
      if (length(parts) < 2) {
        print "release is not trusted: manifest asset missing sha256" > "/dev/stderr"
        exit 4
      }
      hash = substr(parts[2], 1, 64)
      if (length(hash) != 64 || hash !~ /^[0-9A-Fa-f]+$/) {
        print "release is not trusted: manifest asset sha256 is invalid" > "/dev/stderr"
        exit 5
      }
      print tolower(hash)
      exit 0
    }
  '
}

verify_signed_manifest() {
  manifest_file="$1"
  signature_file="$2"
  asset_name="$3"
  version="$4"

  need_cmd openssl
  if [ ! -f "$manifest_file" ] || [ ! -f "$signature_file" ]; then
    echo "release is not trusted: signed release manifest or signature is missing. For local release testing, publish release-manifest.json and release-manifest.rsa.sig and set EXCEEDS_INK_RELEASE_PUBLIC_KEY_PEM to the PEM public key that signed it." >&2
    exit 1
  fi

  key_file="$(mktemp "${TMPDIR:-/tmp}/exceeds-ink-release-key.XXXXXX")"
  sig_file="$(mktemp "${TMPDIR:-/tmp}/exceeds-ink-release-sig.XXXXXX")"
  release_public_key_pem > "$key_file"
  if ! tr -d '\r\n\t ' < "$signature_file" | openssl base64 -d -A -out "$sig_file" >/dev/null 2>&1; then
    rm -f "$key_file" "$sig_file"
    echo "release is not trusted: release manifest signature is not valid base64." >&2
    echo "For local release testing, set EXCEEDS_INK_RELEASE_PUBLIC_KEY_PEM to the PEM public key that signed the manifest." >&2
    exit 1
  fi
  if ! openssl dgst -sha256 -verify "$key_file" -signature "$sig_file" "$manifest_file" >/dev/null 2>&1; then
    rm -f "$key_file" "$sig_file"
    echo "release is not trusted: RSA-SHA256 release manifest signature verification failed." >&2
    echo "For local release testing, set EXCEEDS_INK_RELEASE_PUBLIC_KEY_PEM to the PEM public key that signed the manifest." >&2
    exit 1
  fi
  rm -f "$key_file" "$sig_file"
  manifest_asset_sha256 "$manifest_file" "$asset_name" "$version" || exit 1
}

verify_archive_sha256() {
  file="$1"
  expected="$2"

  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$file" | awk '{print $1}')"
  else
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  fi

  if [ "$expected" != "$actual" ]; then
    echo "SHA256 verification failed for $file" >&2
    exit 1
  fi
}

endpoint_override_flag() {
  endpoint="$1"
  case "$endpoint" in
    https://exceeds-ink.vercel.app/api/v1/ingest)
      printf '%s' "--official-endpoint"
      ;;
    http://127.0.0.1:*|http://localhost:*|https://127.0.0.1:*|https://localhost:*)
      printf '%s' "--dev-endpoint"
      ;;
    https://*)
      printf '%s' "--allow-custom-endpoint"
      ;;
    http://*)
      printf '%s' "--allow-custom-endpoint"
      ;;
    *)
      echo "Unsupported endpoint override: $endpoint" >&2
      exit 1
      ;;
  esac
}

resolve_endpoint_trust_flag() {
  expected_flag="$(endpoint_override_flag "$EFF_COMPAT")"
  if [ -n "$ENDPOINT_TRUST_FLAG" ]; then
    printf '%s' "$ENDPOINT_TRUST_FLAG"
    return
  fi
  if [ "$expected_flag" = "--official-endpoint" ] && [ "$EFF_OTLP_HTTP" = "$DEFAULT_OTLP_HTTP" ]; then
    printf '%s' "--official-endpoint"
    return
  fi
  echo "Non-official endpoint overrides require explicit trust intent. Re-run with --dev-endpoint for localhost/dev endpoints or --allow-custom-endpoint for custom endpoints." >&2
  exit 1
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

kv_value() {
  key="$1"
  content="$2"
  printf '%s\n' "$content" | awk -F= -v target="$key" '
    $1 == target {
      print substr($0, index($0, "=") + 1)
      exit
    }
  '
}

run_machine_registration() {
  install_path="$1"
  status_output="$("$install_path" machine status 2>&1)" || {
    printf '%s\n' "$status_output" >&2
    exit 1
  }
  registered="$(kv_value machine_registered "$status_output")"
  if [ "$registered" = "yes" ]; then
    echo "Machine already registered."
    return
  fi

  echo "Running exceeds-ink machine pair..."
  pair_output="$("$install_path" machine pair 2>&1)" || {
    printf '%s\n' "$pair_output" >&2
    exit 1
  }
  printf '%s\n' "$pair_output"

  pairing_id="$(kv_value machine_pairing_id "$pair_output")"
  if [ -z "$pairing_id" ]; then
    echo "Machine pairing did not return a pairing id." >&2
    exit 1
  fi

  deadline_epoch=$(( $(date +%s) + INSTALLER_REGISTRATION_TIMEOUT_SECONDS ))
  last_status=""
  while :; do
    status_output="$("$install_path" machine status 2>&1)" || {
      printf '%s\n' "$status_output" >&2
      exit 1
    }
    registered="$(kv_value machine_registered "$status_output")"
    pairing_status="$(kv_value pairing_status "$status_output")"
    remote_pairing_status="$(kv_value remote_pairing_status "$status_output")"
    if [ "$registered" = "yes" ]; then
      echo "Machine registration complete."
      printf '%s\n' "$status_output"
      return
    fi

    effective_status="$remote_pairing_status"
    if [ -z "$effective_status" ]; then
      effective_status="$pairing_status"
    fi
    if [ -z "$effective_status" ]; then
      effective_status="pending"
    fi

    case "$effective_status" in
      rejected|expired)
        echo "Machine registration failed with status: $effective_status" >&2
        printf '%s\n' "$status_output" >&2
        exit 1
        ;;
    esac

    if [ "$effective_status" != "$last_status" ]; then
      echo "Waiting for machine approval (pairing $pairing_id, status: $effective_status)..."
      last_status="$effective_status"
    fi
    if [ "$(date +%s)" -ge "$deadline_epoch" ]; then
      echo "Timed out waiting for machine registration approval." >&2
      printf '%s\n' "$status_output" >&2
      exit 1
    fi
    sleep "$INSTALLER_REGISTRATION_POLL_SECONDS"
  done
}

run_setup_and_install() {
  install_path="$1"
  resolve_effective_endpoints
  ENDPOINT_FLAG="$(resolve_endpoint_trust_flag)" || exit 1

  echo "Clearing local machine registration state before reinstall..."
  clear_output="$("$install_path" machine clear 2>&1)" || {
    printf '%s\n' "$clear_output" >&2
    exit 1
  }
  printf '%s\n' "$clear_output"

  echo "Running exceeds-ink setup (collector: Exceeds Vercel or your overrides)..."
  set -- "$install_path" setup \
    "$ENDPOINT_FLAG" \
    --otlp-http-endpoint "$EFF_OTLP_HTTP" \
    --compat-endpoint "$EFF_COMPAT"
  if [ -n "$OTLP_GRPC_ENDPOINT" ]; then
    set -- "$@" --otlp-grpc-endpoint "$OTLP_GRPC_ENDPOINT"
  fi
  if [ -n "$API_KEY" ]; then
    set -- "$@" --api-key "$API_KEY"
  fi
  EXCEEDS_INK_INSTALLER_MACHINE_REGISTRATION=1 "$@" || exit 1

  run_machine_registration "$install_path"

  echo "Running exceeds-ink install --all..."
  set -- "$install_path" install --all \
    "$ENDPOINT_FLAG" \
    --otlp-http-endpoint "$EFF_OTLP_HTTP" \
    --compat-endpoint "$EFF_COMPAT"
  if [ -n "$OTLP_GRPC_ENDPOINT" ]; then
    set -- "$@" --otlp-grpc-endpoint "$OTLP_GRPC_ENDPOINT"
  fi
  if [ -n "$API_KEY" ]; then
    set -- "$@" --api-key "$API_KEY"
  fi
  EXCEEDS_INK_INSTALLER_MACHINE_REGISTRATION=1 "$@" || exit 1
}

shell_family() {
  shell_path="${1:-${SHELL:-}}"
  shell_name="${shell_path##*/}"
  case "$shell_name" in
    sh|ash|bash|dash|ksh|zsh)
      printf '%s' "posix"
      ;;
    fish)
      printf '%s' "fish"
      ;;
    *)
      printf '%s' "unknown"
      ;;
  esac
}

path_contains_dir() {
  target_dir="$1"
  case ":$PATH:" in
    *":$target_dir:"*) return 0 ;;
    *) return 1 ;;
  esac
}

print_path_guidance() {
  install_dir="$1"
  case "$(shell_family "${2:-${SHELL:-}}")" in
    fish)
      echo "Add exceeds-ink to your PATH (fish):"
      echo "  fish_add_path \"$install_dir\""
      ;;
    posix)
      echo "Add exceeds-ink to your PATH:"
      echo "  export PATH=\"$install_dir:\$PATH\""
      ;;
    *)
      echo "Add exceeds-ink to your PATH:"
      echo "  Your shell was not recognized automatically."
      echo "  Add $install_dir to your PATH using your shell's startup file."
      ;;
  esac
}

print_post_install_summary() {
  install_dir="$1"
  install_path="$2"
  binary_only="$3"

  path_ready=0
  if path_contains_dir "$install_dir"; then
    path_ready=1
  else
    echo
    print_path_guidance "$install_dir"
    echo "  Open a new shell or reload your shell config afterward."
  fi

  echo
  echo "Next steps:"
  if [ "$path_ready" = "1" ]; then
    echo "  1. Run 'exceeds-ink --version' to confirm the install."
  else
    echo "  1. Run '$install_path --version' to confirm the install immediately."
    echo "  2. After updating your PATH, open a new shell and run 'exceeds-ink --version'."
  fi
  if [ "$binary_only" = "1" ]; then
    if [ "$path_ready" = "1" ]; then
      echo "  2. Run 'exceeds-ink setup' / 'exceeds-ink install' as needed, or re-run this installer without --binary-only."
      echo "  3. Run 'exceeds-ink init' inside each repo you want to track."
    else
      echo "  3. Run 'exceeds-ink setup' / 'exceeds-ink install' as needed, or re-run this installer without --binary-only."
      echo "  4. Run 'exceeds-ink init' inside each repo you want to track."
    fi
  else
    if [ "$path_ready" = "1" ]; then
      echo "  2. Run 'exceeds-ink init' inside each repo you want to track."
    else
      echo "  3. Run 'exceeds-ink init' inside each repo you want to track."
    fi
  fi
}

if [ "${EXCEEDS_INK_INSTALLER_SOURCE_ONLY:-0}" = "1" ]; then
  return 0 2>/dev/null || exit 0
fi

need_cmd curl
need_cmd tar
need_cmd mktemp
need_cmd awk
need_cmd openssl

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
MANIFEST_PATH="$TMP_DIR/$RELEASE_MANIFEST_NAME"
SIGNATURE_PATH="$TMP_DIR/$RELEASE_MANIFEST_SIG_NAME"

if [ -n "$DOWNLOAD_BASE" ]; then
  echo "Downloading ${ASSET} from ${BASE_URL}..."
else
  echo "Downloading ${ASSET} from ${REPO}..."
fi
curl -fsSL "$BASE_URL/$ASSET" -o "$ARCHIVE_PATH"
curl -fsSL "$BASE_URL/$RELEASE_MANIFEST_NAME" -o "$MANIFEST_PATH"
curl -fsSL "$BASE_URL/$RELEASE_MANIFEST_SIG_NAME" -o "$SIGNATURE_PATH"
EXPECTED_SHA256="$(verify_signed_manifest "$MANIFEST_PATH" "$SIGNATURE_PATH" "$ASSET" "$RESOLVED_VERSION")" || exit 1
verify_archive_sha256 "$ARCHIVE_PATH" "$EXPECTED_SHA256"

mkdir -p "$INSTALL_DIR"
tar -xzf "$ARCHIVE_PATH" -C "$TMP_DIR"
install_path="$INSTALL_DIR/exceeds-ink"
cp "$TMP_DIR/exceeds-ink" "$install_path"
chmod 755 "$install_path"

echo "Installed exceeds-ink to $install_path"

if [ "$BINARY_ONLY" != "1" ]; then
  run_setup_and_install "$install_path"
fi

print_post_install_summary "$INSTALL_DIR" "$install_path" "$BINARY_ONLY"
