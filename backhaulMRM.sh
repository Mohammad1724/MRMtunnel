#!/bin/bash
# ==============================================================================
# backhaulMRM v4.5 - FINAL FIXED & AUDITED
# Fork of ArminNy/Backhaul_Premium
# Fixes: CPU high (busy loop) + disconnect (keepalive 30s) + UI + service log
# Features: Lightweight 396 lines, Secure token, Simple menu, Cron, View/Edit
# ==============================================================================
SCRIPT_VERSION="v4.5-MRM"
CORE_VERSION="v6.0-MRM"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'
CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; NC=$'\033[0m'

CONFIG_DIR="/root/backhaul-core"
SERVICE_DIR="/etc/systemd/system"
BIN_PATH="$CONFIG_DIR/backhaulMRM"
LOG_DIR="$CONFIG_DIR/logs"

mkdir -p "$CONFIG_DIR" "$LOG_DIR"
[[ $EUID -ne 0 ]] && { echo -e "${RED}Must be root${NC}"; exit 1; }

log_i(){ echo -e "${GREEN}[INFO]${NC} $1"; }
log_w(){ echo -e "${YELLOW}[WARN]${NC} $1"; }
log_e(){ echo -e "${RED}[ERR]${NC} $1"; }
cprint(){ echo -e "${BOLD}${CYAN}$1${NC}"; }

gen_token(){ openssl rand -hex 16 2>/dev/null || tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32; echo; }
sanitize(){ echo "$1" | tr -d '"' | tr -d '`' | tr -d '$' | tr -d ';' | tr -d '&' | tr -d '|' | tr -d '>' | tr -d '<'; }

install_deps(){
  local need=()
  for p in curl openssl; do command -v $p &>/dev/null || need+=($p); done
  command -v ss &>/dev/null || need+=("iproute2")
  [[ ${#need[@]} -eq 0 ]] && return
  if command -v apt-get &>/dev/null; then apt-get update -y -qq && apt-get install -y "${need[@]}" -qq
  elif command -v dnf &>/dev/null; then dnf install -y "${need[@]}" -q
  elif command -v yum &>/dev/null; then yum install -y "${need[@]}" -q; fi
}

check_port(){ ss -tlnH "sport = :$1" 2>/dev/null | grep -q ":$1" && return 0 || return 1; }

fw_allow(){
  local p=$1
  if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "active"; then
    ufw allow "$p"/tcp >/dev/null 2>&1; ufw allow "$p"/udp >/dev/null 2>&1
  elif command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --add-port="$p/tcp" --add-port="$p/udp" >/dev/null 2>&1; firewall-cmd --reload >/dev/null 2>&1
  else
    iptables -C INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -p tcp --dport "$p" -j ACCEPT 2>/dev/null
    iptables -C INPUT -p udp --dport "$p" -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -p udp --dport "$p" -j ACCEPT 2>/dev/null
  fi
}

download_core(){
  local mode=${1:-}
  [[ -f "$BIN_PATH" && "$mode" != "force" ]] && return
  [[ "$mode" == "force" ]] && rm -f "$BIN_PATH"
  mkdir -p "$CONFIG_DIR" "$LOG_DIR"
  local arch=$(uname -m); local url=""
  case "$arch" in
    x86_64|amd64) url="https://github.com/Mohammad1724/backhaulMRM/releases/download/v6.0-MRM/backhaulMRM_linux_amd64";;
    aarch64|arm64) url="https://github.com/Mohammad1724/backhaulMRM/releases/download/v6.0-MRM/backhaulMRM_linux_arm64";;
    *) url="https://raw.githubusercontent.com/ArminNy/Backhaul_Premium/refs/heads/main/backhaul-patch";;
  esac
  log_i "Downloading backhaulMRM core..."
  if ! curl -fsSL -o "$BIN_PATH" "$url" 2>/dev/null; then
    log_w "Super core not in releases, using original v1.1.9..."
    url="https://raw.githubusercontent.com/ArminNy/Backhaul_Premium/refs/heads/main/backhaul-patch"
    curl -fsSL -o "$BIN_PATH" "$url" 2>/dev/null || { log_e "Download failed"; exit 1; }
  fi
  chmod +x "$BIN_PATH"
  local v=$("$BIN_PATH" -v 2>&1 | grep -oE "v[0-9]+\.[0-9.]+" | head -n1)
  [[ -z "$v" ]] && v="$CORE_VERSION"
  log_i "Core installed: $v"
}

# SUPER FIX: Auto-migrate old service files with append logs -> journal
fix_old_services(){
  local fixed=0
  for svc_file in "$SERVICE_DIR"/backhaulMRM-*.service "$SERVICE_DIR"/backhaul-*.service; do
    [[ -f "$svc_file" ]] || continue
    if grep -q "StandardOutput=append" "$svc_file"; then
      sed -i 's|StandardOutput=append.*|StandardOutput=journal|' "$svc_file"
      sed -i 's|StandardError=append.*|StandardError=journal|' "$svc_file"
      if ! grep -q "ExecStartPre" "$svc_file"; then
        sed -i '/^\[Service\]/a ExecStartPre=/bin/mkdir -p /root/backhaul-core/logs' "$svc_file"
      fi
      fixed=$((fixed+1))
    fi
    # Also ensure binary path exists, if not, try to fix ExecStart to use correct binary
    if [[ ! -x "$BIN_PATH" ]]; then
      # Try to find any backhaul binary
      local alt_bin=$(ls "$CONFIG_DIR"/backhaul* 2>/dev/null | head -n1)
      if [[ -x "$alt_bin" && "$alt_bin" != "$BIN_PATH" ]]; then
        ln -sf "$alt_bin" "$BIN_PATH"
      fi
    fi
  done
  if [[ $fixed -gt 0 ]]; then
    systemctl daemon-reload 2>/dev/null || true
    log_i "Fixed $fixed old service files (append -> journal)"
  fi
}


get_val(){ grep -E "^\s*$2\s*=" "$1" | head -1 | cut -d'=' -f2- | tr -d '"' | tr -d "'" | xargs 2>/dev/null || echo "-"; }
get_ports(){ sed -n '/ports = \[/,/\]/p' "$1" | grep '"' | tr -d ' ' | tr -d '"' | tr -d ',' | paste -sd "," -; }
validate_ports(){
  local input="$1"; local out=""
  IFS=',' read -ra arr <<< "$input"
  for p in "${arr[@]}"; do
    p=$(echo "$p" | tr -d ' ')
    [[ -z "$p" ]] && continue
    # Accept any with = - : pattern as valid (user knows format)
    if [[ "$p" == *"="* || "$p" == *"-"* || "$p" == *":"* || "$p" =~ ^[0-9]+$ ]]; then
      [[ -z "$out" ]] && out="$p" || out="$out,$p"
    else
      log_w "Invalid port ignored: $p"
    fi
  done
  echo "$out"
}

show_details(){
  local cfg="$1"; local name=$(basename "$cfg" .toml); local svc="backhaulMRM-${name}.service"
  [[ -f "$SERVICE_DIR/$svc" ]] || svc="backhaul-${name}.service"
  clear; cprint "=== Details: $name ==="; echo ""
  echo "File: $cfg"
  echo "Service: $svc"
  echo "Status: $(systemctl is-active "$svc" 2>/dev/null || echo "inactive")"
  echo "----------------------------------------"
  local trans=$(get_val "$cfg" "transport")
  local bind=$(get_val "$cfg" "bind_addr"); [[ "$bind" == "-" ]] && bind=$(get_val "$cfg" "remote_addr")
  local token=$(get_val "$cfg" "token")
  local token_mask="${token:0:4}****${token: -4}"
  local nodelay=$(get_val "$cfg" "nodelay")
  local keepalive=$(get_val "$cfg" "keepalive_period")
  local heartbeat=$(get_val "$cfg" "heartbeat")
  local channel=$(get_val "$cfg" "channel_size")
  local mux_con=$(get_val "$cfg" "mux_con")
  local mux_ver=$(get_val "$cfg" "mux_version")
  local web_port=$(get_val "$cfg" "web_port")
  local ports=$(get_ports "$cfg")
  echo "Transport: $trans"
  echo "Bind/Remote: $bind"
  echo "Token: $token_mask (len=${#token})"
  echo "Ports: $ports"
  echo "TCP_NODELAY: $nodelay"
  echo "Keepalive: ${keepalive}s"
  echo "Heartbeat: ${heartbeat}s"
  echo "Channel: $channel"
  echo "Mux Con: $mux_con"
  echo "Mux Ver: $mux_ver"
  echo "Web Port: $web_port"
  echo "----------------------------------------"
  cat "$cfg"
}

edit_tunnel(){
  local cfg="$1"; local name=$(basename "$cfg" .toml)
  local svc="backhaulMRM-${name}.service"; [[ -f "$SERVICE_DIR/$svc" ]] || svc="backhaul-${name}.service"
  while true; do
    clear; cprint "=== Edit: $name ==="
    echo "Current ports: $(get_ports "$cfg") | transport: $(get_val "$cfg" "transport") | nodelay: $(get_val "$cfg" "nodelay")"
    echo ""
    echo "  1) Ports"
    echo "  2) Token"
    echo "  3) Transport"
    echo "  4) Nodelay"
    echo "  5) Keepalive/Heartbeat"
    echo "  6) Mux Con & Version"
    echo "  7) Channel Size"
    echo "  8) Web Port"
    echo "  9) Bind/Remote Addr"
    echo "  0) Back & Restart"
    read -rp "Choice: " ec
    case $ec in
      1) read -rp "New ports: " np; np=$(validate_ports "$np"); [[ -z "$np" ]] && continue; tmp=$(mktemp); awk -v ports="$np" 'BEGIN{in=0} /ports = \[/{print; in=1; n=split(ports, a, ","); for(i in a) if(a[i]!="") print "  \""a[i]"\","; next} /^\]/{if(in==1){print; in=0; next}} {if(in==0) print}' "$cfg" > "$tmp" && mv "$tmp" "$cfg"; chmod 600 "$cfg";;
      2) read -rp "New token (Enter auto): " nt; nt=${nt:-$(gen_token)}; nt=$(sanitize "$nt"); [[ ${#nt} -lt 16 ]] && { log_e "Min 16"; continue; }; sed -i "s/^token = .*/token = \"$nt\"/" "$cfg"; chmod 600 "$cfg";;
      3) read -rp "Transport [tcp/tcpmux/ws/wsmux/faketcp/udp]: " nt; [[ "$nt" == wss ]] && nt=wsmux; [[ "$nt" =~ ^(tcp|tcpmux|ws|wsmux|faketcp|udp)$ ]] && sed -i "s/^transport = .*/transport = \"$nt\"/" "$cfg" || log_e "Invalid";;
      4) read -rp "Nodelay true/false [true]: " nd; nd=${nd:-true}; [[ "$nd" == true || "$nd" == false ]] && sed -i "s/^nodelay = .*/nodelay = $nd/" "$cfg" || log_e "true/false";;
      5) read -rp "Keepalive [30]: " ka; ka=${ka:-30}; read -rp "Heartbeat [30]: " hb; hb=${hb:-30}; sed -i "s/^keepalive_period = .*/keepalive_period = $ka/" "$cfg"; sed -i "s/^heartbeat = .*/heartbeat = $hb/" "$cfg";;
      6) read -rp "Mux Con [8]: " mc; mc=${mc:-8}; read -rp "Mux Ver 1/2 [2]: " mv; mv=${mv:-2}; sed -i "s/^mux_con = .*/mux_con = $mc/" "$cfg"; sed -i "s/^mux_version = .*/mux_version = $mv/" "$cfg";;
      7) read -rp "Channel [2048]: " cs; cs=${cs:-2048}; sed -i "s/^channel_size = .*/channel_size = $cs/" "$cfg";;
      8) read -rp "Web Port [0]: " wp; wp=${wp:-0}; sed -i "s/^web_port = .*/web_port = $wp/" "$cfg";;
      9) if [[ "$name" == iran* ]]; then read -rp "bind_addr [:3080]: " ba; [[ -n "$ba" ]] && sed -i "s/^bind_addr = .*/bind_addr = \"$ba\"/" "$cfg"; else read -rp "remote_addr: " ra; [[ -n "$ra" ]] && sed -i "s|^remote_addr = .*|remote_addr = \"$ra\"|" "$cfg"; fi;;
      0) systemctl daemon-reload; systemctl restart "$svc" && log_i "Restarted" || log_e "Failed"; break;;
    esac
    sleep 1
  done
}

cron_menu(){
  clear; cprint "=== Cronjob (backhaulMRM) ==="; echo ""
  echo "Current:"; crontab -l 2>/dev/null | grep -E "backhaulMRM|backhaul" || echo "(none)"; echo ""
  echo "1) Add for specific tunnel"
  echo "2) Add for ALL"
  echo "3) Remove all"
  echo "4) List"
  echo "0) Back"
  read -rp "Choice: " cc
  case $cc in
    1)
      local i=1; declare -a svcs
      for f in "$CONFIG_DIR"/iran*.toml "$CONFIG_DIR"/kharej*.toml; do [[ -f "$f" ]] || continue; local n=$(basename "$f" .toml); svcs+=("backhaulMRM-${n}.service"); [[ -f "$SERVICE_DIR/${svcs[-1]}" ]] || svcs[-1]="backhaul-${n}.service"; echo "$i) ${svcs[-1]}"; ((i++)); done
      read -rp "Select number: " tn; local svc="${svcs[$((tn-1))]}"; [[ -z "$svc" ]] && return
      echo "1) Every 1h  2) Every 6h  3) 12h  4) Daily 3AM  5) 30m  6) Custom"
      read -rp "Choice: " sc; local ce=""
      case $sc in 1) ce="0 * * * *";; 2) ce="0 */6 * * *";; 3) ce="0 */12 * * *";; 4) ce="0 3 * * *";; 5) ce="*/30 * * * *";; 6) read -rp "Custom: " ce;; esac
      (crontab -l 2>/dev/null || true; echo "$ce /bin/systemctl restart $svc >/dev/null 2>&1 # backhaulMRM-$svc") | crontab -
      log_i "Added $ce for $svc"
      ;;
    2) read -rp "1)6h 2)Daily 3)1h: " sc; local ce="0 */6 * * *"; case $sc in 1) ce="0 */6 * * *";; 2) ce="0 3 * * *";; 3) ce="0 * * * *";; esac; (crontab -l 2>/dev/null || true; echo "$ce /bin/systemctl restart backhaulMRM-* backhaul-* >/dev/null 2>&1 # backhaulMRM-all") | crontab -; log_i "Added for all";;
    3) (crontab -l 2>/dev/null || true; crontab -l 2>/dev/null | grep -v "backhaulMRM" | grep -v "backhaul-" || true) | crontab - 2>/dev/null || true; crontab -l 2>/dev/null | grep -v "backhaul" | crontab - 2>/dev/null || true; log_i "Removed";;
    4) crontab -l 2>/dev/null | grep -E "backhaulMRM|backhaul" || echo "No crons"; read -rp "Enter...";;
    0) return;;
  esac
  sleep 1
}


choose_transport(){
  echo -e "  ${GREEN}1) tcpmux  - Most stable for Iran (RECOMMENDED)${NC}" >&2
  echo -e "  2) tcp     - Simple, low RAM" >&2
  echo -e "  3) wsmux   - For CDN/Cloudflare (bypass DPI)" >&2
  echo -e "  4) ws      - WebSocket simple" >&2
  echo -e "  5) faketcp - Obfuscation (fake TCP)" >&2
  echo -e "  6) udp     - For lossy networks" >&2
  echo "" >&2
  while true; do
    read -rp "[*] Choose transport [1-6 or name, default tcpmux]: " ch
    ch=${ch:-tcpmux}
    case "$ch" in
      1|tcpmux) echo "tcpmux"; return;;
      2|tcp) echo "tcp"; return;;
      3|wsmux|wss) echo "wsmux"; return;;
      4|ws) echo "ws"; return;;
      5|faketcp) echo "faketcp"; return;;
      6|udp) echo "udp"; return;;
      tcpmux|tcp|ws|wsmux|faketcp|udp) echo "$ch"; return;;
      *) log_e "Invalid, choose 1-6 or tcpmux/tcp/ws/wsmux/faketcp/udp" >&2;;
    esac
  done
}


create_iran(){
  clear; cprint "=== IRAN Server (backhaulMRM) ==="; echo ""
  if [[ ! -x "$BIN_PATH" ]]; then log_w "Core not found, downloading..."; download_core force; fi
  echo -e "${DIM}Step 1/4 - Tunnel Port${NC}"
  local port="" trans="" token="" ports=""
  while true; do read -rp "[*] Tunnel port [3080]: " port; port=${port:-3080}; [[ "$port" =~ ^[0-9]+$ && $port -gt 22 && $port -le 65535 ]] || { log_e "Invalid port 23-65535"; continue; }; check_port "$port" && { log_e "Port $port in use"; continue; }; break; done

  echo ""; echo -e "${DIM}Step 2/4 - Transport Type${NC}"
  echo -e "  Available transports:"
  trans=$(choose_transport)
  log_i "Selected transport: $trans"

  echo ""; echo -e "${DIM}Step 3/4 - Security Token${NC}"
  echo "  Token authenticates IRAN <-> KHAREJ, keep it secret!"
  echo "  Must be >=16 chars"
  local auto_tok=$(gen_token)
  echo -e "  Auto-generated: ${GREEN}${auto_tok}${NC}"
  echo -e "  ${DIM}Press Enter to use auto, or paste your own${NC}"
  read -rp "[*] Token [auto]: " token
  token=$(sanitize "${token:-$auto_tok}")
  [[ ${#token} -lt 16 ]] && { log_w "Too short, using auto"; token=$auto_tok; }
  echo -e "  Using token: ${YELLOW}${token:0:8}****${NC} len=${#token}"

  echo ""; echo -e "${DIM}Step 4/4 - Port Forwarding${NC}"
  echo "  Format: LISTEN=FORWARD"
  echo "    443=443         Iran 443 -> Kharej 443"
  echo "    443=8443        Iran 443 -> Kharej 8443"
  echo "    10000-50000     Range forwarding"
  echo "  Example: 443=443,80=80,10000-50000"
  read -rp "[*] Ports (comma separated): " ports
  ports=$(validate_ports "$ports")
  [[ -z "$ports" ]] && { log_e "No valid ports"; return; }
  log_i "Ports: $ports"

  echo ""; read -rp "Advanced settings? (y/n) [n]: " adv
  local nodelay="true"; local keepalive="30"; local heartbeat="30"; local channel="2048"; local mux_con="8"; local mux_ver="2"; local web_port="0"
  if [[ "$adv" == "y" || "$adv" == "Y" ]]; then
    echo ""; cprint "--- Advanced (IRAN) ---"
    read -rp "  TCP_NODELAY true/false [true]: " nodelay; nodelay=${nodelay:-true}
    read -rp "  Keepalive [30]: " keepalive; keepalive=${keepalive:-30}
    read -rp "  Heartbeat [30]: " heartbeat; heartbeat=${heartbeat:-30}
    read -rp "  Channel Size [2048]: " channel; channel=${channel:-2048}
    read -rp "  Mux Con [8]: " mux_con; mux_con=${mux_con:-8}
    read -rp "  Mux Version 1/2 [2]: " mux_ver; mux_ver=${mux_ver:-2}
    read -rp "  Web Port 0=disable [0]: " web_port; web_port=${web_port:-0}
  else
    echo -e "${DIM}  Using defaults: nodelay=true keepalive=30 heartbeat=30 channel=2048 mux_con=8 mux_ver=2 web_port=0${NC}"
  fi

  local cfg="$CONFIG_DIR/iran${port}.toml"
  cat << EOF > "$cfg"
# backhaulMRM IRAN - $(date -Iseconds)
# Transport: $trans | Nodelay: $nodelay | Keepalive: $keepalive
[server]
bind_addr = ":${port}"
transport = "${trans}"
token = "${token}"
keepalive_period = ${keepalive}
nodelay = ${nodelay}
channel_size = ${channel}
heartbeat = ${heartbeat}
mux_con = ${mux_con}
mux_version = ${mux_ver}
mux_framesize = 32768
mux_recievebuffer = 4194304
mux_streambuffer = 65536
sniffer = false
web_port = ${web_port}
sniffer_log = "${LOG_DIR}/iran${port}.json"
log_level = "info"
proxy_protocol = false

ports = [
EOF
  IFS=',' read -ra arr <<< "$ports"
  for p in "${arr[@]}"; do echo "  "$p"," >> "$cfg"; done
  echo "]" >> "$cfg"
  chmod 600 "$cfg"
  cat << EOF > "$SERVICE_DIR/backhaulMRM-iran${port}.service"
[Unit]
Description=backhaulMRM IRAN $port
After=network.target
StartLimitBurst=5
StartLimitIntervalSec=180

[Service]
Type=simple
ExecStartPre=/bin/mkdir -p $LOG_DIR
ExecStart=$BIN_PATH -c $cfg
Restart=always
RestartSec=3
LimitNOFILE=1048576
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload; fw_allow "$port" tcp; fw_allow "$port" udp
  for pp in "${arr[@]}"; do base=$(echo "$pp" | cut -d'=' -f1 | cut -d':' -f1 | cut -d'-' -f1); [[ "$base" =~ ^[0-9]+$ ]] && fw_allow "$base" tcp; done
  systemctl enable --now "backhaulMRM-iran${port}.service" && { echo ""; cprint "✅ backhaulMRM IRAN $port started!"; echo "Token: $token (save it for KHAREJ)"; } || log_e "Failed to start"
  read -rp "Press Enter..."
}


create_kharej(){
  clear; cprint "=== KHAREJ Server (backhaulMRM) ==="; echo ""
  if [[ ! -x "$BIN_PATH" ]]; then log_w "Core not found, downloading..."; download_core force; fi
  echo -e "${DIM}Step 1/4 - IRAN Info${NC}"
  local iran_ip="" port="" token="" trans=""
  while true; do read -rp "[*] IRAN IP/Domain: " iran_ip; [[ -n "$iran_ip" ]] && break; log_e "IRAN IP required"; done
  while true; do read -rp "[*] Tunnel port (same as IRAN) [3080]: " port; port=${port:-3080}; [[ "$port" =~ ^[0-9]+$ ]] && break; log_e "Invalid port"; done

  echo ""; echo -e "${DIM}Step 2/4 - Transport Type (must match IRAN)${NC}"
  echo -e "  Available transports:"
  trans=$(choose_transport)
  log_i "Selected transport: $trans (must match IRAN: $trans)"

  echo ""; echo -e "${DIM}Step 3/4 - Security Token (must match IRAN)${NC}"
  echo "  ${YELLOW}⚠️  If you haven't setup IRAN server yet, go back and setup IRAN first!${NC}"
  echo "  Paste SAME token from IRAN server (/root/backhaul-core/*.toml)"
  echo "  Token must be >=16 chars"
  while true; do
    read -rp "[*] Token (paste from IRAN): " token
    token=$(sanitize "$token")
    if [[ -z "$token" ]]; then
      log_e "Token is required! Tunnel NOT created."; log_e "Paste same token from IRAN. If no IRAN yet, press Ctrl+C and setup IRAN first (option 2 in main menu is IRAN)"
      continue
    fi
    if [[ ${#token} -lt 16 ]]; then
      log_e "Token too weak! len=${#token} < 16 - Tunnel NOT created."; log_e "Must be >=16 and same as IRAN. Generate on IRAN with: openssl rand -hex 16"
      continue
    fi
    break
  done
  echo -e "  Token OK: ${YELLOW}${token:0:8}****${NC} len=${#token}"

  echo ""; echo -e "${DIM}Step 4/4 - Advanced${NC}"
  local nodelay="true"; local pool="8"; local retry="1"; local dial="5"; local mux_ver="2"; local web_port="0"
  read -rp "Advanced settings? (y/n) [n]: " adv
  if [[ "$adv" == "y" || "$adv" == "Y" ]]; then
    echo ""; cprint "--- Advanced (KHAREJ) ---"
    read -rp "  TCP_NODELAY true/false [true]: " nodelay; nodelay=${nodelay:-true}
    read -rp "  Connection Pool [8]: " pool; pool=${pool:-8}
    read -rp "  Retry Interval [1]: " retry; retry=${retry:-1}
    read -rp "  Dial Timeout [5]: " dial; dial=${dial:-5}
    read -rp "  Mux Version 1/2 [2]: " mux_ver; mux_ver=${mux_ver:-2}
    read -rp "  Web Port 0=disable [0]: " web_port; web_port=${web_port:-0}
  else
    echo -e "${DIM}  Using defaults: nodelay=true pool=8 retry=1 dial=5 mux_ver=2 web_port=0${NC}"
  fi

  local cfg="$CONFIG_DIR/kharej${port}.toml"
  cat << EOF > "$cfg"
# backhaulMRM KHAREJ - $(date -Iseconds)
# Transport: $trans | Nodelay: $nodelay | Pool: $pool | IRAN: $iran_ip:$port
[client]
remote_addr = "${iran_ip}:${port}"
transport = "${trans}"
token = "${token}"
connection_pool = ${pool}
aggressive_pool = true
keepalive_period = 30
nodelay = ${nodelay}
retry_interval = ${retry}
dial_timeout = ${dial}
mux_version = ${mux_ver}
mux_framesize = 32768
mux_recievebuffer = 4194304
mux_streambuffer = 65536
sniffer = false
web_port = ${web_port}
sniffer_log = "${LOG_DIR}/kharej${port}.json"
log_level = "info"
EOF
  chmod 600 "$cfg"
  cat << EOF > "$SERVICE_DIR/backhaulMRM-kharej${port}.service"
[Unit]
Description=backhaulMRM KHAREJ $port
After=network.target

[Service]
Type=simple
ExecStartPre=/bin/mkdir -p $LOG_DIR
ExecStart=$BIN_PATH -c $cfg
Restart=always
RestartSec=3
LimitNOFILE=1048576
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now "backhaulMRM-kharej${port}.service" && cprint "✅ backhaulMRM KHAREJ $port -> $iran_ip:$port" || log_e "Failed to start"
  read -rp "Press Enter..."
}


list_tunnels(){
  clear; cprint "Tunnels (backhaulMRM v4.5):"; echo ""
  local i=1; declare -a files
  for f in "$CONFIG_DIR"/iran*.toml "$CONFIG_DIR"/kharej*.toml; do [[ -f "$f" ]] || continue; local name=$(basename "$f" .toml); local svc="backhaulMRM-${name}.service"; [[ -f "$SERVICE_DIR/$svc" ]] || svc="backhaul-${name}.service"; local state=$(systemctl is-active "$svc" 2>/dev/null || echo "inactive"); local trans=$(get_val "$f" "transport"); echo -e "$i) $name -> $state [${YELLOW}$trans${NC}]"; files+=("$f"); ((i++)); done
  [[ ${#files[@]} -eq 0 ]] && { log_e "No tunnels"; read -rp "Enter..."; return; }
  echo ""; read -rp "Select number (0 return): " sel; [[ "$sel" == 0 || -z "$sel" ]] && return
  local cfg="${files[$((sel-1))]}"; [[ -z "$cfg" ]] && return; local name=$(basename "$cfg" .toml); local svc="backhaulMRM-${name}.service"; [[ -f "$SERVICE_DIR/$svc" ]] || svc="backhaul-${name}.service"
  while true; do
    clear; cprint "Manage: $name"
    echo "  1) View full details"
    echo "  2) View raw config"
    echo "  3) Edit tunnel"
    echo "  4) Restart"
    echo "  5) Logs"
    echo "  6) Status"
    echo "  7) Cronjob"
    echo "  8) Remove"
    echo "  0) Back"
    read -rp "Choice: " ch
    case $ch in
      1) show_details "$cfg"; read -rp "Enter...";;
      2) cat "$cfg"; read -rp "Enter...";;
      3) edit_tunnel "$cfg";;
      4) systemctl restart "$svc" && log_i "Restarted"; sleep 1;;
      5) journalctl -u "$svc" -f --no-pager;;
      6) systemctl status "$svc" --no-pager; read -rp "Enter...";;
      7) cron_menu;;
      8) read -rp "Sure remove $name? (y/n): " yn; [[ "$yn" == y* ]] && { systemctl disable --now "$svc" 2>/dev/null; rm -f "$cfg" "$SERVICE_DIR/$svc"; systemctl daemon-reload; (crontab -l 2>/dev/null || true | grep -v "$name" | crontab - 2>/dev/null || true); log_i "Removed"; }; read -rp "Enter..."; break;;
      0) break;;
    esac
  done
}

status_all(){
  clear; cprint "Status Detailed (backhaulMRM v4.5):"; echo ""
  for f in "$CONFIG_DIR"/iran*.toml "$CONFIG_DIR"/kharej*.toml; do [[ -f "$f" ]] || continue; local n=$(basename "$f" .toml); local s="backhaulMRM-${n}.service"; [[ -f "$SERVICE_DIR/$s" ]] || s="backhaul-${n}.service"; local trans=$(get_val "$f" "transport"); local ports=$(get_ports "$f"); local nodelay=$(get_val "$f" "nodelay"); if systemctl is-active --quiet "$s"; then echo -e "${GREEN}✔ $n RUNNING${NC} [${YELLOW}$trans${NC}] ports:${ports} nodelay:${nodelay}"; else echo -e "${RED}✘ $n STOPPED${NC} [${YELLOW}$trans${NC}] ports:${ports}"; fi; done
  echo ""; echo "Cron jobs:"; crontab -l 2>/dev/null | grep -E "backhaulMRM|backhaul" || echo "(no cron)"; echo ""; read -rp "Enter..."
}

optimize(){
  clear; cprint "Optimize BBR (backhaulMRM safe)"; read -rp "Continue? (y/n): " yn; [[ "$yn" != y* ]] && return
  cat << EOF > /etc/sysctl.d/99-backhaulMRM.conf
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.somaxconn = 65536
net.ipv4.tcp_max_syn_backlog = 20480
EOF
  sysctl -p /etc/sysctl.d/99-backhaulMRM.conf 2>&1 | tail -5
  log_i "Optimized"
  read -rp "Enter..."
}

get_core_status(){
  if [[ -x "$BIN_PATH" ]]; then
    local ver=$("$BIN_PATH" -v 2>&1 | grep -oE "v[0-9]+\.[0-9.]+" | head -n1); ver=$(echo "$ver" | tr -d "█╗║═╚╝╔" | xargs)
    [[ -z "$ver" ]] && ver="Installed"
    echo "Installed $ver"
  else
    echo "Not Installed - Choose 1 to Install"
  fi
}

install_deps
download_core
fix_old_services

while true; do
  clear
  echo "=================================================="
  echo "  backhaulMRM v4.5 - CLEAN & AUDITED"
  echo "  Lightweight | Secure | Simple | Efficient"
  echo "=================================================="
  ip=$(hostname -I 2>/dev/null | awk '{print $1}' | tr -d ' ')
  if [[ -z "$ip" ]]; then
    ip=$(curl -s --max-time 2 https://api.ipify.org 2>/dev/null || echo "Unknown")
    if [[ "$ip" == *"<html>"* ]]; then ip="Unknown"; fi
  fi
  core_st=$(get_core_status)
  tunnel_cnt=$(ls "$CONFIG_DIR"/*.toml 2>/dev/null | wc -l | tr -d ' ')
  [[ -z "$tunnel_cnt" ]] && tunnel_cnt=0
  echo "  IP: $ip"
  echo "  Core: $core_st"
  echo "  Tunnels: $tunnel_cnt"
  echo "  Version: $SCRIPT_VERSION"
  echo "--------------------------------------------------"
  echo "  1) Install / Update Core"
  echo "  2) Create IRAN tunnel"
  echo "  3) Create KHAREJ tunnel"
  echo "  4) List / Manage + View / Edit"
  echo "  5) Status detailed"
  echo "  6) Cronjob Auto Restart"
  echo "  7) Optimize BBR"
  echo "  8) Uninstall Core"
  echo "  0) Exit"
  echo "--------------------------------------------------"
  read -rp "Choice [0-8]: " c
  case $c in
    1) download_core force; read -rp "Press Enter...";;
    2) create_iran;;
    3) create_kharej;;
    4) list_tunnels;;
    5) status_all;;
    6) cron_menu;;
    7) optimize;;
    8) ls "$CONFIG_DIR"/*.toml 1>/dev/null 2>&1 && { log_e "Delete tunnels first!"; sleep 2; } || { read -rp "Remove core? (y/n): " yn; [[ "$yn" == y* ]] && rm -rf "$CONFIG_DIR" && log_i "Removed"; sleep 1; };;
    0) exit 0;;
    *) log_e "Invalid"; sleep 1;;
  esac
done
