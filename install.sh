#!/usr/bin/env bash
set -euo pipefail

# rodctl installer
# Downloads prebuilt binary from GitHub releases, falls back to build from source.

REPO="notcandy001/rodctl"
BIN_NAME="rodctl"
INSTALL_DIR="/usr/local/bin"

# ── Colors ────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m' CYAN='\033[0;36m' YELLOW='\033[1;33m' RED='\033[0;31m' NC='\033[0m'
info()    { echo -e "${CYAN}→  $1${NC}"; }
success() { echo -e "${GREEN}✓  $1${NC}"; }
warn()    { echo -e "${YELLOW}!  $1${NC}"; }
error()   { echo -e "${RED}✗  $1${NC}" >&2; exit 1; }

# ── NixOS fast path ───────────────────────────────────────────────────────────
if [[ -f /etc/NIXOS ]] || ([ -f /etc/os-release ] && grep -qi nixos /etc/os-release 2>/dev/null); then
  command -v nix >/dev/null 2>&1 || error "NixOS detected but nix is unavailable."
  info "NixOS detected — installing via nix profile…"
  nix profile add "github:${REPO}"
  success "rodctl installed via nix"
  exit 0
fi

# ── OS / arch detection ───────────────────────────────────────────────────────
os="$(uname -s)"
arch="$(uname -m)"
[[ "$os" == "Linux" ]] || error "Unsupported OS: $os"

case "$arch" in
  x86_64)               asset="${BIN_NAME}_linux_amd64"  ;;
  i386|i686)            asset="${BIN_NAME}_linux_386"    ;;
  aarch64)              asset="${BIN_NAME}_linux_arm64"  ;;
  armv7l|armv7|armv6l)  asset="${BIN_NAME}_linux_armv7" ;;
  *)                    error "Unsupported architecture: $arch" ;;
esac

# ── Version helpers ───────────────────────────────────────────────────────────
normalize_version() {
  echo "$1" | sed -E 's/^v//' | grep -Eo '[0-9]+(\.[0-9]+)*' | head -n1 || true
}

# ── Fetch latest release tag ──────────────────────────────────────────────────
release_api="https://api.github.com/repos/${REPO}/releases/latest"
info "Fetching latest release info…"

build_from_source=false
latest_tag=""
latest_tag="$(curl -fsL "$release_api" 2>/dev/null | \
  grep -E '"tag_name"\s*:' | head -n1 | \
  sed -E 's/.*"tag_name"\s*:\s*"([^"]+)".*/\1/')" || true

if [[ -z "$latest_tag" ]]; then
  warn "Could not reach GitHub API — will build from source."
  build_from_source=true
else
  latest_version="$(normalize_version "$latest_tag")"
  # Check if already up to date
  if command -v "$BIN_NAME" >/dev/null 2>&1; then
    current_raw="$("$BIN_NAME" version 2>/dev/null || true)"
    current_version="$(normalize_version "$current_raw")"
    if [[ -n "$current_version" && -n "$latest_version" ]]; then
      if [[ "$(printf '%s\n%s\n' "$current_version" "$latest_version" | sort -V | head -n1)" == "$latest_version" ]]; then
        success "rodctl already up to date (${current_version})"
        exit 0
      fi
    fi
  fi
fi

# ── Temp file setup ───────────────────────────────────────────────────────────
tmp="$(mktemp)"
cleanup() { rm -f "$tmp"; }
trap cleanup EXIT

# ── Try prebuilt binary ───────────────────────────────────────────────────────
if [[ "$build_from_source" == "false" ]]; then
  url="https://github.com/${REPO}/releases/download/${latest_tag}/${asset}"
  info "Downloading ${asset} (${latest_tag})…"
  if ! curl -fL "$url" -o "$tmp" 2>/dev/null; then
    warn "Prebuilt binary unavailable for ${asset} — building from source…"
    build_from_source=true
  fi
fi

# ── Build from source ─────────────────────────────────────────────────────────
if [[ "$build_from_source" == "true" ]]; then
  command -v go >/dev/null 2>&1 || \
    error "Go is not installed. Install it from https://go.dev/dl/ and retry."

  src_dir="$(mktemp -d)"
  trap "rm -rf '$src_dir'; rm -f '$tmp'" EXIT

  info "Cloning rodctl source…"
  git clone --depth=1 "https://github.com/${REPO}.git" "$src_dir" 2>/dev/null

  info "Building rodctl…"
  (cd "$src_dir" && go build -ldflags="-s -w" -o "$tmp" .) || error "Build failed."
  success "Build complete"
fi

# ── Install binary ────────────────────────────────────────────────────────────
chmod +x "$tmp"

do_install() {
  install -m 755 "$tmp" "${1}/${BIN_NAME}"
}

if [[ $EUID -eq 0 ]]; then
  do_install "$INSTALL_DIR"
elif command -v sudo >/dev/null 2>&1; then
  sudo install -m 755 "$tmp" "${INSTALL_DIR}/${BIN_NAME}"
else
  mkdir -p "$HOME/.local/bin"
  do_install "$HOME/.local/bin"
  INSTALL_DIR="$HOME/.local/bin"
  warn "sudo not found — installed to ~/.local/bin"
  warn "Make sure ~/.local/bin is in your PATH"
fi

success "Installed ${INSTALL_DIR}/${BIN_NAME}"
echo ""
echo "   Run: rodctl help"
echo "   Start daemon: rodctl daemon &"
