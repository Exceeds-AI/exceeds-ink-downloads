#!/bin/sh
set -eu

# Public Exceeds collector (Vercel). Override both OTLP + compat together if you use a different host.
DEFAULT_OTLP_HTTP="https://ink-staging.exceeds.ai/api/v1/otlp"
DEFAULT_COMPAT="https://ink-staging.exceeds.ai/api/v1/ingest"
TERMS_URL="https://ink-staging.exceeds.ai/tos"
RELEASE_MANIFEST_NAME="release-manifest.json"
RELEASE_MANIFEST_SIG_NAME="release-manifest.rsa.sig"

REPO="${EXCEEDS_INK_REPO:-Exceeds-AI/exceeds-ink-downloads}"
INSTALL_DIR="${EXCEEDS_INK_INSTALL_DIR:-/usr/local/bin}"
VERSION="${EXCEEDS_INK_VERSION:-staging-v0.1.44-2}"
REQUIRE_EXPLICIT_VERSION=1
STAGING_RELEASE_INSTALLER=1
DOWNLOAD_BASE="${EXCEEDS_INK_DOWNLOAD_BASE_URL:-}"
COMPAT_ENDPOINT="${EXCEEDS_INK_COMPAT_ENDPOINT:-}"
OTLP_HTTP_ENDPOINT="${EXCEEDS_INK_OTLP_HTTP_ENDPOINT:-}"
OTLP_GRPC_ENDPOINT="${EXCEEDS_INK_OTLP_GRPC_ENDPOINT:-}"
API_KEY="${EXCEEDS_INK_API_KEY:-}"
INSTALLER_REGISTRATION_TIMEOUT_SECONDS="${EXCEEDS_INK_INSTALLER_REGISTRATION_TIMEOUT_SECONDS:-600}"
INSTALLER_REGISTRATION_POLL_SECONDS="${EXCEEDS_INK_INSTALLER_REGISTRATION_POLL_SECONDS:-5}"
ENDPOINT_TRUST_FLAG=""
MDM_FLAG=""
USER_EMAIL=""
LOCAL_BINARY=""
BINARY_ONLY=0
INSTALL_VSCODE_EXTENSION=1

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
You must accept the Exceeds Ink Terms of Service before setup/install runs:
https://ink-staging.exceeds.ai/tos
Afterward run `exceeds-ink init` in each git repo you want to track.

Optional flags:
  --version <version>             Install a specific version (for example: 0.1.0)
  --install-dir <path>            Override install directory (default: /usr/local/bin)
  --download-base <url>           Override the public asset base URL
  --repo <owner/name>             Override the GitHub repository used for releases
  --binary-only                   Only download and install the binary (skip setup / install --all)
  --local-binary <path>           Install from a local exceeds-ink binary instead of downloading
  --no-vscode-extension           Skip VS Code/Cursor extension download and install
  --compat-endpoint <url>         Override compat ingest (requires --otlp-http-endpoint too)
  --otlp-http-endpoint <url>      Override OTLP HTTP (requires --compat-endpoint too)
  --otlp-grpc-endpoint <url>      Optional; passed through when set
  --api-key <key>                 Optional; passed to setup and install when set
  --mdm                           Non-interactive MDM install (auto-init repos, auto-link machine)
  --user-email <email>            MDM profile email (requires --mdm; overrides git email deduction)
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
    --local-binary)
      LOCAL_BINARY="$2"
      shift 2
      ;;
    --no-vscode-extension)
      INSTALL_VSCODE_EXTENSION=0
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
    --mdm)
      MDM_FLAG="--mdm"
      shift 1
      ;;
    --user-email)
      USER_EMAIL="$2"
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

case "$(printf '%s' "${EXCEEDS_INK_INSTALL_VSCODE_EXTENSION:-}" | tr '[:upper:]' '[:lower:]')" in
  0|false|no|off) INSTALL_VSCODE_EXTENSION=0 ;;
esac

case "$(printf '%s' "${EXCEEDS_INK_MDM:-}" | tr '[:upper:]' '[:lower:]')" in
  1|true|yes|on) MDM_FLAG="--mdm" ;;
esac

if [ -z "$LOCAL_BINARY" ] && [ -n "${EXCEEDS_INK_LOCAL_BINARY:-}" ]; then
  LOCAL_BINARY="$EXCEEDS_INK_LOCAL_BINARY"
fi

if [ -z "$USER_EMAIL" ] && [ -n "${EXCEEDS_INK_MDM_USER_EMAIL:-}" ]; then
  USER_EMAIL="$EXCEEDS_INK_MDM_USER_EMAIL"
fi

validate_user_email() {
  if [ -z "$USER_EMAIL" ]; then
    return 0
  fi
  if [ -z "$MDM_FLAG" ]; then
    echo "--user-email requires --mdm" >&2
    exit 1
  fi
  case "$USER_EMAIL" in
    *@*) ;;
    *)
      echo "Invalid --user-email: expected an email address containing @" >&2
      exit 1
      ;;
  esac
}

validate_user_email

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 1
  fi
}

normalize_stable_semver() {
  candidate="$(printf '%s' "$1" | tr -d '\r' | awk '{print $1}')"
  candidate="${candidate#v}"
  if printf '%s' "$candidate" | awk 'BEGIN { ok = 0 } /^[0-9]+\.[0-9]+\.[0-9]+$/ { ok = 1 } END { exit ok ? 0 : 1 }'; then
    printf '%s' "$candidate"
    return 0
  fi
  return 1
}

staging_asset_version_from_tag() {
  candidate="$(printf '%s' "$1" | tr -d '\r' | awk '{print $1}')"
  candidate="${candidate#staging-v}"
  candidate="${candidate#v}"
  printf '%s\n' "$candidate" | awk '
    /^[0-9]+\.[0-9]+\.[0-9]+$/ {
      print $0 "-staging.0"
      found = 1
    }
    /^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+$/ {
      split($0, parts, "-")
      print parts[1] "-staging." parts[2]
      found = 1
    }
    /^[0-9]+\.[0-9]+\.[0-9]+-staging\.[0-9]+$/ {
      print $0
      found = 1
    }
    END {
      exit found ? 0 : 1
    }
  '
}

staging_release_tag_from_asset_version() {
  asset_version="$1"
  printf '%s\n' "$asset_version" | awk '
    /^[0-9]+\.[0-9]+\.[0-9]+-staging\.[0-9]+$/ {
      split($0, parts, "-staging.")
      if (parts[2] == "0") {
        print "staging-v" parts[1]
      } else {
        print "staging-v" parts[1] "-" parts[2]
      }
      found = 1
    }
    END {
      exit found ? 0 : 1
    }
  '
}

select_highest_stable_semver_from_releases_json() {
  json="$1"
  printf '%s\n' "$json" | awk -F'"' '
    function is_stable(tag) {
      return tag ~ /^v?[0-9]+\.[0-9]+\.[0-9]+$/
    }
    function strip_v(tag) {
      sub(/^v/, "", tag)
      return tag
    }
    function greater(a, b,    pa, pb, i) {
      split(a, pa, ".")
      split(b, pb, ".")
      for (i = 1; i <= 3; i++) {
        if ((pa[i] + 0) > (pb[i] + 0)) {
          return 1
        }
        if ((pa[i] + 0) < (pb[i] + 0)) {
          return 0
        }
      }
      return 0
    }
    /"tag_name":/ {
      tag = $4
      if (is_stable(tag)) {
        version = strip_v(tag)
        if (best == "" || greater(version, best)) {
          best = version
        }
      }
    }
    END {
      if (best != "") {
        print best
      }
    }
  '
}

resolve_release_metadata() {
  if [ "$REQUIRE_EXPLICIT_VERSION" = "1" ] && { [ -z "$VERSION" ] || [ "$VERSION" = "latest" ]; }; then
    echo "This is a staging installer. Specify an explicit version via --version <version> or EXCEEDS_INK_VERSION." >&2
    exit 1
  fi
  if [ "$VERSION" != "latest" ]; then
    if [ "$STAGING_RELEASE_INSTALLER" = "1" ]; then
      RESOLVED_VERSION="$(staging_asset_version_from_tag "$VERSION" || true)"
      if [ -z "$RESOLVED_VERSION" ]; then
        echo "Invalid staging version '$VERSION' (expected X.Y.Z, X.Y.Z-N, staging-vX.Y.Z, or staging-vX.Y.Z-N)." >&2
        exit 1
      fi
      RESOLVED_RELEASE_TAG="$(staging_release_tag_from_asset_version "$RESOLVED_VERSION")"
      return
    fi
    RESOLVED_VERSION="$(normalize_stable_semver "$VERSION" || true)"
    if [ -z "$RESOLVED_VERSION" ]; then
      echo "Invalid version '$VERSION' (expected X.Y.Z or vX.Y.Z)." >&2
      exit 1
    fi
    RESOLVED_RELEASE_TAG="v${RESOLVED_VERSION}"
    return
  fi

  if [ -n "$DOWNLOAD_BASE" ]; then
    latest_url="${DOWNLOAD_BASE%/}/LATEST"
    latest_version="$(curl -fsSL "$latest_url" 2>/dev/null | tr -d '\r' | awk 'NF { print; exit }' || true)"
    if [ "$STAGING_RELEASE_INSTALLER" = "1" ]; then
      latest_version="$(staging_asset_version_from_tag "$latest_version" || true)"
    else
      latest_version="$(normalize_stable_semver "$latest_version" || true)"
    fi
    if [ -n "$latest_version" ]; then
      RESOLVED_VERSION="$latest_version"
      if [ "$STAGING_RELEASE_INSTALLER" = "1" ]; then
        RESOLVED_RELEASE_TAG="$(staging_release_tag_from_asset_version "$RESOLVED_VERSION")"
      else
        RESOLVED_RELEASE_TAG="v${RESOLVED_VERSION}"
      fi
      return
    fi
  fi

  latest_json="$(curl -fsSL -H 'Accept: application/vnd.github+json' "https://api.github.com/repos/$REPO/releases/latest")"
  latest_tag="$(printf '%s\n' "$latest_json" | awk -F'"' '/"tag_name":/ { print $4; exit }')"
  latest_version="$(normalize_stable_semver "$latest_tag" || true)"
  if [ -n "$latest_version" ]; then
    RESOLVED_VERSION="$latest_version"
    RESOLVED_RELEASE_TAG="v${RESOLVED_VERSION}"
    return
  fi

  releases_json="$(curl -fsSL -H 'Accept: application/vnd.github+json' "https://api.github.com/repos/$REPO/releases?per_page=30")"
  latest_version="$(select_highest_stable_semver_from_releases_json "$releases_json" || true)"
  if [ -z "$latest_version" ]; then
    echo "Failed to resolve latest release for $REPO" >&2
    if [ -n "$DOWNLOAD_BASE" ]; then
      echo "Set EXCEEDS_INK_VERSION or publish ${DOWNLOAD_BASE%/}/LATEST." >&2
    fi
    echo "Ensure releases include at least one stable semver tag (vX.Y.Z)." >&2
    exit 1
  fi
  RESOLVED_VERSION="$latest_version"
  RESOLVED_RELEASE_TAG="v${RESOLVED_VERSION}"
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

resolve_editor_cli() {
  # Echoes a usable editor CLI path for the given editor key, or nothing.
  # Checks PATH first, then well-known install locations so the extension is
  # installed even when the editor's CLI was never added to PATH (common for
  # VS Code on macOS, where users must run "Install 'code' command in PATH").
  editor_key="$1"
  if command -v "$editor_key" >/dev/null 2>&1; then
    command -v "$editor_key"
    return 0
  fi

  # Sourced for tests: only honor PATH so fake CLIs and skip behavior stay deterministic.
  if [ "${EXCEEDS_INK_INSTALLER_SOURCE_ONLY:-0}" = "1" ]; then
    return 1
  fi

  case "$editor_key" in
    code)
      candidates="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code
$HOME/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code
/usr/share/code/bin/code
/usr/bin/code
/snap/bin/code"
      ;;
    code-insiders)
      candidates="/Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/bin/code
$HOME/Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/bin/code
/usr/share/code-insiders/bin/code-insiders
/usr/bin/code-insiders
/snap/bin/code-insiders"
      ;;
    cursor)
      candidates="/Applications/Cursor.app/Contents/Resources/app/bin/cursor
$HOME/Applications/Cursor.app/Contents/Resources/app/bin/cursor
/usr/share/cursor/bin/cursor
/usr/bin/cursor"
      ;;
    *)
      candidates=""
      ;;
  esac

  old_ifs="$IFS"
  IFS='
'
  for candidate in $candidates; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
      IFS="$old_ifs"
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  IFS="$old_ifs"
  return 1
}

install_vscode_extension() {
  vsix_path="$1"

  if [ "$INSTALL_VSCODE_EXTENSION" != "1" ]; then
    echo "Skipping VS Code/Cursor extension install (disabled)."
    return 0
  fi

  installed=0
  for editor_key in cursor code code-insiders; do
    editor_cli="$(resolve_editor_cli "$editor_key")"
    if [ -n "$editor_cli" ]; then
      echo "Installing Exceeds Ink extension with $editor_key ($editor_cli)..."
      NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }--no-deprecation" "$editor_cli" --install-extension "$vsix_path" --force
      echo "Installed Exceeds Ink extension with $editor_key."
      installed=1
    fi
  done

  if [ "$installed" != "1" ]; then
    echo "Skipping VS Code/Cursor extension install; no VS Code, VS Code Insiders, or Cursor install was found."
  fi
}

endpoint_override_flag() {
  endpoint="$1"
  case "$endpoint" in
    https://ink-staging.exceeds.ai/api/v1/ingest)
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

tty_available() {
  # Subshell keeps a failed /dev/tty open from tripping set -e in dash.
  ( : < /dev/tty ) >/dev/null 2>&1
}

confirm_terms_acceptance() {
  if [ -n "$MDM_FLAG" ]; then
    return 0
  fi
  echo "Please review the Exceeds Ink Terms of Service before setup/install:"
  echo "  $TERMS_URL"
  printf "Do you accept the Exceeds Ink Terms of Service? [y/N] "
  answer=""
  if tty_available; then
    IFS= read -r answer < /dev/tty || answer=""
  else
    IFS= read -r answer || answer=""
  fi
  case "$answer" in
    y|Y|yes|YES|Yes)
      return 0
      ;;
    *)
      echo "Terms of Service were not accepted. Aborting install." >&2
      exit 1
      ;;
  esac
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

run_installer_cli() {
  install_path="$1"
  shift
  if [ -n "$MDM_FLAG" ] && [ -n "$USER_EMAIL" ]; then
    run_installer_command "$install_path" "$MDM_FLAG" --user-email "$USER_EMAIL" "$@"
  elif [ -n "$MDM_FLAG" ]; then
    run_installer_command "$install_path" "$MDM_FLAG" "$@"
  else
    run_installer_command "$install_path" "$@"
  fi
}

run_machine_bootstrap_cli() {
  install_path="$1"
  shift
  if [ -n "$MDM_FLAG" ] && [ -n "$USER_EMAIL" ]; then
    run_machine_bootstrap_command "$install_path" "$MDM_FLAG" --user-email "$USER_EMAIL" "$@"
  elif [ -n "$MDM_FLAG" ]; then
    run_machine_bootstrap_command "$install_path" "$MDM_FLAG" "$@"
  else
    run_machine_bootstrap_command "$install_path" "$@"
  fi
}

resolve_target_user() {
  if [ "$(id -u)" -eq 0 ]; then
    if [ "$(uname -s)" = "Darwin" ]; then
      /usr/bin/stat -f%Su /dev/console 2>/dev/null || true
      return
    fi
    if command -v logname >/dev/null 2>&1; then
      logname 2>/dev/null || true
      return
    fi
    printf '%s' "${SUDO_USER:-${USER:-}}"
    return
  fi
  printf '%s' "${USER:-$(id -un)}"
}

resolve_target_home() {
  user="$1"
  if [ -z "$user" ]; then
    return 1
  fi
  if [ "$(uname -s)" = "Darwin" ] && command -v dscl >/dev/null 2>&1; then
    home="$(dscl . -read "/Users/$user" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
    if [ -n "$home" ]; then
      printf '%s' "$home"
      return 0
    fi
  fi
  getent passwd "$user" 2>/dev/null | cut -d: -f6 || eval "printf '%s' ~$user"
}

ensure_user_home_layout() {
  install_path="$1"
  target_user="$(resolve_target_user)"
  target_home="$(resolve_target_home "$target_user")"
  if [ -z "$target_user" ] || [ -z "$target_home" ]; then
    echo "Could not resolve target user home for exceeds-ink layout." >&2
    exit 1
  fi
  legacy_binary="$target_home/.exceeds-ink/bin/exceeds-ink"
  if [ "$(id -u)" -eq 0 ] && [ "$target_user" != "$(id -un)" ]; then
    need_cmd sudo
    sudo -u "$target_user" mkdir -p "$target_home/.exceeds-ink/bin"
    sudo -u "$target_user" ln -sf "$install_path" "$legacy_binary"
  else
    mkdir -p "$target_home/.exceeds-ink/bin"
    ln -sf "$install_path" "$legacy_binary"
  fi
  echo "Linked $legacy_binary -> $install_path"
}

run_with_target_context() {
  if [ "$(id -u)" -eq 0 ]; then
    target_user="$(resolve_target_user)"
    target_home="$(resolve_target_home "$target_user")"
    if [ -z "$target_user" ] || [ "$target_user" = "root" ] || [ -z "$target_home" ]; then
      echo "Could not resolve console user for exceeds-ink bootstrap." >&2
      exit 1
    fi
    need_cmd sudo
    sudo -u "$target_user" env HOME="$target_home" "$@"
    return
  fi
  "$@"
}

run_machine_bootstrap_command() {
  install_path="$1"
  shift
  if [ -n "$MDM_FLAG" ] && [ -n "$USER_EMAIL" ]; then
    run_with_target_context env \
      EXCEEDS_INK_ALLOW_RUNTIME_REMOTE_ENDPOINT_ENV=1 \
      EXCEEDS_INK_REMOTE_INGEST_ENDPOINT="$EFF_COMPAT" \
      EXCEEDS_INK_REMOTE_API_KEY="$API_KEY" \
      EXCEEDS_INK_DISABLE_AUTO_UPGRADE=1 \
      EXCEEDS_INK_MDM=1 \
      EXCEEDS_INK_MDM_USER_EMAIL="$USER_EMAIL" \
      "$install_path" "$@"
  elif [ -n "$MDM_FLAG" ]; then
    run_with_target_context env \
      EXCEEDS_INK_ALLOW_RUNTIME_REMOTE_ENDPOINT_ENV=1 \
      EXCEEDS_INK_REMOTE_INGEST_ENDPOINT="$EFF_COMPAT" \
      EXCEEDS_INK_REMOTE_API_KEY="$API_KEY" \
      EXCEEDS_INK_DISABLE_AUTO_UPGRADE=1 \
      EXCEEDS_INK_MDM=1 \
      "$install_path" "$@"
  else
    run_with_target_context env \
      EXCEEDS_INK_ALLOW_RUNTIME_REMOTE_ENDPOINT_ENV=1 \
      EXCEEDS_INK_REMOTE_INGEST_ENDPOINT="$EFF_COMPAT" \
      EXCEEDS_INK_REMOTE_API_KEY="$API_KEY" \
      EXCEEDS_INK_DISABLE_AUTO_UPGRADE=1 \
      "$install_path" "$@"
  fi
}

run_machine_registration() {
  install_path="$1"
  status_output="$(run_machine_bootstrap_cli "$install_path" machine status 2>&1)" || {
    printf '%s\n' "$status_output" >&2
    exit 1
  }
  registered="$(kv_value machine_registered "$status_output")"
  if [ "$registered" = "yes" ]; then
    echo "Machine already registered."
    return
  fi

  echo "Running exceeds-ink machine pair..."
  if [ -n "$MDM_FLAG" ]; then
    pair_output="$(run_machine_bootstrap_cli "$install_path" machine pair --no-browser 2>&1)" || {
      printf '%s\n' "$pair_output" >&2
      exit 1
    }
  else
    pair_output="$(run_machine_bootstrap_cli "$install_path" machine pair 2>&1)" || {
      printf '%s\n' "$pair_output" >&2
      exit 1
    }
  fi
  printf '%s\n' "$pair_output"

  pairing_id="$(kv_value machine_pairing_id "$pair_output")"
  if [ -z "$pairing_id" ]; then
    echo "Machine pairing did not return a pairing id." >&2
    exit 1
  fi

  deadline_epoch=$(( $(date +%s) + INSTALLER_REGISTRATION_TIMEOUT_SECONDS ))
  last_status=""
  while :; do
    status_output="$(run_machine_bootstrap_cli "$install_path" machine status 2>&1)" || {
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
  export EXCEEDS_INK_DISABLE_AUTO_UPGRADE=1

  confirm_terms_acceptance
  resolve_effective_endpoints
  ENDPOINT_FLAG="$(resolve_endpoint_trust_flag)" || exit 1

  echo "Clearing local machine registration state before reinstall..."
  clear_output="$(run_installer_cli "$install_path" machine clear 2>&1)" || {
    printf '%s\n' "$clear_output" >&2
    exit 1
  }
  printf '%s\n' "$clear_output"

  echo "Running exceeds-ink setup (collector: Exceeds Vercel or your overrides)..."
  if [ -n "$OTLP_GRPC_ENDPOINT" ] && [ -n "$API_KEY" ]; then
    run_installer_cli "$install_path" setup \
      "$ENDPOINT_FLAG" \
      --otlp-http-endpoint "$EFF_OTLP_HTTP" \
      --compat-endpoint "$EFF_COMPAT" \
      --otlp-grpc-endpoint "$OTLP_GRPC_ENDPOINT" \
      --api-key "$API_KEY" || exit 1
  elif [ -n "$OTLP_GRPC_ENDPOINT" ]; then
    run_installer_cli "$install_path" setup \
      "$ENDPOINT_FLAG" \
      --otlp-http-endpoint "$EFF_OTLP_HTTP" \
      --compat-endpoint "$EFF_COMPAT" \
      --otlp-grpc-endpoint "$OTLP_GRPC_ENDPOINT" || exit 1
  elif [ -n "$API_KEY" ]; then
    run_installer_cli "$install_path" setup \
      "$ENDPOINT_FLAG" \
      --otlp-http-endpoint "$EFF_OTLP_HTTP" \
      --compat-endpoint "$EFF_COMPAT" \
      --api-key "$API_KEY" || exit 1
  else
    run_installer_cli "$install_path" setup \
      "$ENDPOINT_FLAG" \
      --otlp-http-endpoint "$EFF_OTLP_HTTP" \
      --compat-endpoint "$EFF_COMPAT" || exit 1
  fi

  run_machine_registration "$install_path"

  echo "Running exceeds-ink install --all..."
  if [ -n "$OTLP_GRPC_ENDPOINT" ] && [ -n "$API_KEY" ]; then
    run_installer_cli "$install_path" install --all \
      "$ENDPOINT_FLAG" \
      --otlp-http-endpoint "$EFF_OTLP_HTTP" \
      --compat-endpoint "$EFF_COMPAT" \
      --otlp-grpc-endpoint "$OTLP_GRPC_ENDPOINT" \
      --api-key "$API_KEY" || exit 1
  elif [ -n "$OTLP_GRPC_ENDPOINT" ]; then
    run_installer_cli "$install_path" install --all \
      "$ENDPOINT_FLAG" \
      --otlp-http-endpoint "$EFF_OTLP_HTTP" \
      --compat-endpoint "$EFF_COMPAT" \
      --otlp-grpc-endpoint "$OTLP_GRPC_ENDPOINT" || exit 1
  elif [ -n "$API_KEY" ]; then
    run_installer_cli "$install_path" install --all \
      "$ENDPOINT_FLAG" \
      --otlp-http-endpoint "$EFF_OTLP_HTTP" \
      --compat-endpoint "$EFF_COMPAT" \
      --api-key "$API_KEY" || exit 1
  else
    run_installer_cli "$install_path" install --all \
      "$ENDPOINT_FLAG" \
      --otlp-http-endpoint "$EFF_OTLP_HTTP" \
      --compat-endpoint "$EFF_COMPAT" || exit 1
  fi
}

run_installer_command() {
  if [ -n "$MDM_FLAG" ] && [ -n "$USER_EMAIL" ]; then
    if tty_available; then
      run_with_target_context env \
        EXCEEDS_INK_INSTALLER_MACHINE_REGISTRATION=1 \
        EXCEEDS_INK_DISABLE_AUTO_UPGRADE=1 \
        EXCEEDS_INK_MDM=1 \
        EXCEEDS_INK_MDM_USER_EMAIL="$USER_EMAIL" \
        "$@" < /dev/tty
    else
      run_with_target_context env \
        EXCEEDS_INK_INSTALLER_MACHINE_REGISTRATION=1 \
        EXCEEDS_INK_DISABLE_AUTO_UPGRADE=1 \
        EXCEEDS_INK_MDM=1 \
        EXCEEDS_INK_MDM_USER_EMAIL="$USER_EMAIL" \
        "$@"
    fi
  elif [ -n "$MDM_FLAG" ]; then
    if tty_available; then
      run_with_target_context env \
        EXCEEDS_INK_INSTALLER_MACHINE_REGISTRATION=1 \
        EXCEEDS_INK_DISABLE_AUTO_UPGRADE=1 \
        EXCEEDS_INK_MDM=1 \
        "$@" < /dev/tty
    else
      run_with_target_context env \
        EXCEEDS_INK_INSTALLER_MACHINE_REGISTRATION=1 \
        EXCEEDS_INK_DISABLE_AUTO_UPGRADE=1 \
        EXCEEDS_INK_MDM=1 \
        "$@"
    fi
  elif tty_available; then
    run_with_target_context env \
      EXCEEDS_INK_INSTALLER_MACHINE_REGISTRATION=1 \
      EXCEEDS_INK_DISABLE_AUTO_UPGRADE=1 \
      "$@" < /dev/tty
  else
    run_with_target_context env \
      EXCEEDS_INK_INSTALLER_MACHINE_REGISTRATION=1 \
      EXCEEDS_INK_DISABLE_AUTO_UPGRADE=1 \
      "$@"
  fi
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

prepare_install_dir() {
  install_dir="$1"
  if mkdir -p "$install_dir" 2>/dev/null && [ -w "$install_dir" ]; then
    USE_SUDO_INSTALL=0
    return 0
  fi
  if ! command -v sudo >/dev/null 2>&1; then
    echo "Cannot write to $install_dir and sudo is not available." >&2
    exit 1
  fi
  echo "Installing to $install_dir requires elevated permissions."
  sudo mkdir -p "$install_dir" || exit 1
  USE_SUDO_INSTALL=1
}

install_binary() {
  install_src="$1"
  install_path="$2"
  if [ "${USE_SUDO_INSTALL:-0}" = "1" ]; then
    sudo cp "$install_src" "$install_path"
    sudo chmod 755 "$install_path"
  else
    cp "$install_src" "$install_path"
    chmod 755 "$install_path"
  fi
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

install_local_binary() {
  local_binary="$1"
  install_path="$2"

  if [ ! -f "$local_binary" ]; then
    echo "Local binary not found: $local_binary" >&2
    exit 1
  fi
  if [ ! -x "$local_binary" ]; then
    echo "Local binary is not executable: $local_binary" >&2
    exit 1
  fi

  echo "Installing local binary from $local_binary..."
  install_binary "$local_binary" "$install_path"
}

download_and_install_release_binary() {
  TARGET="$(detect_target)"
  RESOLVED_VERSION=""
  RESOLVED_RELEASE_TAG=""
  resolve_release_metadata
  ASSET="exceeds-ink_${RESOLVED_VERSION}_${TARGET}.tar.gz"
  VSIX_ASSET="exceeds-ink-vscode_${RESOLVED_VERSION}.vsix"
  if [ -n "$DOWNLOAD_BASE" ]; then
    BASE_URL="${DOWNLOAD_BASE%/}/${RESOLVED_RELEASE_TAG}"
  else
    BASE_URL="https://github.com/${REPO}/releases/download/${RESOLVED_RELEASE_TAG}"
  fi

  TMP_DIR="$(mktemp -d)"
  cleanup() {
    rm -rf "$TMP_DIR"
  }
  trap cleanup EXIT INT TERM

  ARCHIVE_PATH="$TMP_DIR/$ASSET"
  VSIX_PATH="$TMP_DIR/$VSIX_ASSET"
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

  if [ "$BINARY_ONLY" != "1" ] && [ "$INSTALL_VSCODE_EXTENSION" = "1" ]; then
    echo "Downloading ${VSIX_ASSET} from ${BASE_URL}..."
    curl -fsSL "$BASE_URL/$VSIX_ASSET" -o "$VSIX_PATH"
    EXPECTED_VSIX_SHA256="$(verify_signed_manifest "$MANIFEST_PATH" "$SIGNATURE_PATH" "$VSIX_ASSET" "$RESOLVED_VERSION")" || exit 1
    verify_archive_sha256 "$VSIX_PATH" "$EXPECTED_VSIX_SHA256"
  fi

  prepare_install_dir "$INSTALL_DIR"
  tar -xzf "$ARCHIVE_PATH" -C "$TMP_DIR"
  install_path="$INSTALL_DIR/exceeds-ink"
  install_binary "$TMP_DIR/exceeds-ink" "$install_path"
  echo "Installed exceeds-ink to $install_path"
  ensure_user_home_layout "$install_path"

  if [ "$BINARY_ONLY" != "1" ]; then
    run_setup_and_install "$install_path"
    if [ -f "$VSIX_PATH" ]; then
      install_vscode_extension "$VSIX_PATH"
    fi
  fi

  print_post_install_summary "$INSTALL_DIR" "$install_path" "$BINARY_ONLY"
}

if [ "${EXCEEDS_INK_INSTALLER_SOURCE_ONLY:-0}" = "1" ]; then
  return 0 2>/dev/null || exit 0
fi

if [ -n "$LOCAL_BINARY" ]; then
  prepare_install_dir "$INSTALL_DIR"
  install_path="$INSTALL_DIR/exceeds-ink"
  install_local_binary "$LOCAL_BINARY" "$install_path"
  echo "Installed exceeds-ink to $install_path"
  ensure_user_home_layout "$install_path"
  if [ "$BINARY_ONLY" != "1" ]; then
    run_setup_and_install "$install_path"
  fi
  print_post_install_summary "$INSTALL_DIR" "$install_path" "$BINARY_ONLY"
  exit 0
fi

need_cmd curl
need_cmd tar
need_cmd mktemp
need_cmd awk
need_cmd openssl

download_and_install_release_binary
