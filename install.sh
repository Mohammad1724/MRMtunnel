#!/usr/bin/env bash
#
# MRMtunnel installer - Hybrid v5.0 Pack FINAL
# Repo: https://github.com/Mohammad1724/MRMtunnel
# Installs:
#   /usr/local/bin/mrmtunnel      - Go engine with web panel 7777
#   /usr/local/bin/backhaulMRM    - Shell CLI lightweight (396 lines)
#
# Works from Iran with mirrors
#
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
info() { echo -e "${GREEN}[*]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[x]${NC} $*" >&2; }

BIN_GO="/usr/local/bin/mrmtunnel"
BIN_SH="/usr/local/bin/backhaulMRM"
GO_VERSION="1.23.4"
GO_MIN_MINOR=23
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-/tmp}")" 2>/dev/null && pwd || echo /tmp)"

export GOPROXY="https://mirror-go.runflare.com,https://goproxy.cn,https://goproxy.io,direct"
export GOSUMDB=off
export GOTOOLCHAIN=local

if [[ $EUID -ne 0 ]]; then err "Run as root: sudo bash install.sh"; exit 1; fi

case "$(uname -m)" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) ARCH="amd64" ;;
esac

mkdir -p /etc/mrmtunnel 2>/dev/null || true

download_go() {
  local file="go${GO_VERSION}.linux-${ARCH}.tar.gz" out="$1"
  for u in "https://mirrors.aliyun.com/golang/${file}" "https://golang.google.cn/dl/${file}" "https://go.dev/dl/${file}"; do
    info "Trying $u"
    curl -fsSL --connect-timeout 15 "$u" -o "$out" && return 0
    warn "mirror failed, trying next..."
  done
  return 1
}
go_new_enough() {
  local v; v="$("$1" version 2>/dev/null | grep -oE 'go1\.[0-9]+' | head -1)"; v="${v#go1.}"
  [[ -n "$v" ]] && (( v >= GO_MIN_MINOR ))
}
ensure_go() {
  command -v go >/dev/null 2>&1 && go_new_enough "$(command -v go)" && { info "Go: $(go version)"; return; }
  [[ -x /usr/local/go/bin/go ]] && go_new_enough /usr/local/go/bin/go && { export PATH="/usr/local/go/bin:$PATH"; info "Go: $(go version)"; return; }
  if [[ -n "$(ls "$SCRIPT_DIR"/prerequisite/go*.linux-"${ARCH}".tar.gz 2>/dev/null | head -1 || true)" ]]; then
    local bundled; bundled="$(ls "$SCRIPT_DIR"/prerequisite/go*.linux-"${ARCH}".tar.gz 2>/dev/null | head -1)"
    info "Using bundled Go: $(basename "$bundled")"; rm -rf /usr/local/go && tar -C /usr/local -xzf "$bundled"
    export PATH="/usr/local/go/bin:$PATH"; return
  fi
  warn "Installing Go ${GO_VERSION}..."
  download_go /tmp/go-mrm.tgz || { err "Could not obtain Go"; exit 1; }
  rm -rf /usr/local/go && tar -C /usr/local -xzf /tmp/go-mrm.tgz; export PATH="/usr/local/go/bin:$PATH"; info "$(go version)"
}

# FIXED: Also check for mrmtunnel_linux_amd64 and mrmtunnel_linux_arm64 in root (your current files)
for cand in \
  "$SCRIPT_DIR/mrmtunnel" \
  "$SCRIPT_DIR/mrmtunnel_linux_${ARCH}" \
  "$SCRIPT_DIR/mrmtunnel_linux_amd64" \
  "$SCRIPT_DIR/mrmtunnel_linux_arm64" \
  "$SCRIPT_DIR/backpack" \
  "$SCRIPT_DIR/dist/mrmtunnel-linux-${ARCH}" \
  "$SCRIPT_DIR/dist/backpack-linux-${ARCH}" \
  "$SCRIPT_DIR/prerequisite/mrmtunnel-linux-${ARCH}" \
  "$SCRIPT_DIR/prerequisite/backpack-linux-${ARCH}"; do
  if [[ -f "$cand" && -s "$cand" ]]; then
    info "Installing local prebuilt binary: $(basename "$cand") -> $BIN_GO"
    install -m 0755 "$cand" "$BIN_GO"
    echo "$SCRIPT_DIR" > /etc/mrmtunnel/install_path
    PREBUILT=1
    break
  fi
done

if [[ "${PREBUILT:-}" != "1" ]]; then
  if [[ -f "$SCRIPT_DIR/go.mod" && -f "$SCRIPT_DIR/main.go" ]]; then
    info "Building MRMtunnel Go engine from source..."
    if [[ -d "$SCRIPT_DIR/go" ]]; then rm -rf "$HOME/mrmtunnel-gocache"; mv "$SCRIPT_DIR/go" "$HOME/mrmtunnel-gocache"; fi
    ensure_go; export PATH="/usr/local/go/bin:$PATH"
    go mod download 2>/dev/null || true
    CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o "$BIN_GO" .
    echo "$SCRIPT_DIR" > /etc/mrmtunnel/install_path
  else
    # No source, try downloading binary from GitHub releases as last resort
    warn "No local binary and no source found, trying download from GitHub releases..."
    local rel_url="https://github.com/Mohammad1724/MRMtunnel/releases/download/v5.0-MRM-Pack/mrmtunnel_linux_${ARCH}"
    if curl -fsSL -o "$BIN_GO" "$rel_url" 2>/dev/null; then
      chmod +x "$BIN_GO"
      PREBUILT=1
      info "Downloaded from releases -> $BIN_GO"
    else
      err "No binary found. Please upload mrmtunnel_linux_${ARCH} to your repo root or create a release."
      err "Expected files: mrmtunnel_linux_amd64 or mrmtunnel_linux_arm64 in repo root"
      exit 1
    fi
  fi
fi

# Install shell CLI
if [[ -f "$SCRIPT_DIR/backhaulMRM.sh" ]]; then
  info "Installing shell CLI: backhaulMRM.sh -> $BIN_SH"
  install -m 0755 "$SCRIPT_DIR/backhaulMRM.sh" "$BIN_SH"
  ln -sf "$BIN_SH" /usr/local/bin/backhaul 2>/dev/null || true
  ln -sf "$BIN_SH" /usr/bin/backhaulMRM 2>/dev/null || true
  ln -sf "$BIN_SH" /usr/local/bin/backhaulMRM.sh 2>/dev/null || true
else
  warn "backhaulMRM.sh not found, skipping shell CLI"
fi

chmod +x "$BIN_GO" 2>/dev/null || true
chmod +x "$BIN_SH" 2>/dev/null || true

echo ""
echo -e "${GREEN}Done! MRMtunnel v5.0 Pack installed${NC}"
echo ""
echo -e "  Go engine (full):  ${YELLOW}sudo mrmtunnel${NC}  -> Web panel http://<ip>:7777"
echo -e "  Shell CLI (lite):  ${YELLOW}sudo backhaulMRM${NC}  -> 396 lines, Cron, View/Edit"
echo ""
echo -e "  One-liner shell: ${CYAN}bash <(curl -Ls https://raw.githubusercontent.com/Mohammad1724/MRMtunnel/main/backhaulMRM.sh)${NC}"
echo ""
