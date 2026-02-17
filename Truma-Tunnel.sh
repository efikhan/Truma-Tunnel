#!/usr/bin/env bash
# =============================================================================
# Truma Tunnel Manager – GRE Tunnel + HAProxy Forwarder with Anti-Filter
# =============================================================================
# This script creates GRE tunnels with HAProxy forwarding and optional anti-filter
# features. It uses a custom tunnel name and a user-defined base network (10.x.y.0).
# =============================================================================

if [[ "${DEBUG:-0}" == "1" ]]; then
    set -euo pipefail
    set -x
    DEBUG_LOG="/tmp/truma-debug.log"
    exec 2> >(tee -a "$DEBUG_LOG" >&2)
    echo "===== Debug session started at $(date) =====" >> "$DEBUG_LOG"
else
    set +e
    set +u
fi

export LC_ALL=C

LOG_LINES=()
LOG_MIN=3
LOG_MAX=10
PORT_LIST=()
SELECTED_TZ=""

# -----------------------------------------------------------------------------
# Truma Logo (Pink)
# -----------------------------------------------------------------------------
banner() {
  echo -e "\e[38;5;13m"
  cat <<'EOF'
 ████████╗██████╗ ██╗   ██╗███╗   ███╗ █████╗ 
 ╚══██╔══╝██╔══██╗██║   ██║████╗ ████║██╔══██╗
    ██║   ██████╔╝██║   ██║██╔████╔██║███████║
    ██║   ██╔══██╗██║   ██║██║╚██╔╝██║██╔══██║
    ██║   ██║  ██║╚██████╔╝██║ ╚═╝ ██║██║  ██║
    ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚═╝╚═╝  ╚═╝
          Truma - Tunnel Manager
EOF
  echo -e "\e[0m"
}

add_log() {
  local msg="$1"
  local ts
  ts="$(date +"%H:%M:%S")"
  LOG_LINES+=("[$ts] $msg")
  if ((${#LOG_LINES[@]} > LOG_MAX)); then
    LOG_LINES=("${LOG_LINES[@]: -$LOG_MAX}")
  fi
}

render() {
  clear
  banner
  echo
  local shown_count="${#LOG_LINES[@]}"
  local height=$shown_count
  ((height < LOG_MIN)) && height=$LOG_MIN
  ((height > LOG_MAX)) && height=$LOG_MAX

  echo "┌───────────────────────────── ACTION LOG ─────────────────────────────┐"
  local start_index=0
  if ((${#LOG_LINES[@]} > height)); then
    start_index=$((${#LOG_LINES[@]} - height))
  fi

  local i line
  for ((i=start_index; i<${#LOG_LINES[@]}; i++)); do
    line="${LOG_LINES[$i]}"
    printf "│ %-68s │\n" "$line"
  done

  local missing=$((height - (${#LOG_LINES[@]} - start_index)))
  for ((i=0; i<missing; i++)); do
    printf "│ %-68s │\n" ""
  done

  echo "└──────────────────────────────────────────────────────────────────────┘"
  echo
}

pause_enter() {
  echo
  read -r -p "Press ENTER to return to menu..." _
}

die_soft() {
  add_log "ERROR: $1"
  render
  pause_enter
}

ensure_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Re-running with sudo..."
    exec sudo -E bash "$0" "$@"
  fi
}

trim() { sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' <<<"$1"; }
is_int() { [[ "$1" =~ ^[0-9]+$ ]]; }

valid_octet() {
  local o="$1"
  [[ "$o" =~ ^[0-9]+$ ]] && ((o>=0 && o<=255))
}

valid_ipv4() {
  local ip="$1"
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS='.' read -r a b c d <<<"$ip"
  valid_octet "$a" && valid_octet "$b" && valid_octet "$c" && valid_octet "$d"
}

valid_port() {
  local p="$1"
  is_int "$p" || return 1
  ((p>=1 && p<=65535))
}

valid_tunnel_name() {
  local name="$1"
  [[ "$name" =~ ^[a-zA-Z0-9_]+$ ]]
}

valid_base_network() {
  local net="$1"
  valid_ipv4 "$net" || return 1
  IFS='.' read -r a b c d <<<"$net"
  [[ "$a" == "10" && "$d" == "0" ]]
}

ipv4_set_last_octet() {
  local ip="$1" last="$2"
  IFS='.' read -r a b c d <<<"$ip"
  echo "${a}.${b}.${c}.${last}"
}

ask_until_valid() {
  local prompt="$1" validator="$2" __var="$3"
  local ans=""
  while true; do
    render
    read -r -e -p "$prompt " ans
    ans="$(trim "$ans")"
    if [[ -z "$ans" ]]; then
      add_log "Empty input. Please try again."
      continue
    fi
    if "$validator" "$ans"; then
      printf -v "$__var" '%s' "$ans"
      add_log "OK: $prompt $ans"
      return 0
    else
      add_log "Invalid: $prompt $ans"
      add_log "Please enter a valid value."
    fi
  done
}

# =============================================================================
# Simplified ask_ports: only comma-separated numbers, no ranges
# =============================================================================
ask_ports() {
  local prompt="Forward PORT (e.g., 80,443,2053):"
  local raw=""
  while true; do
    render
    read -r -e -p "$prompt " raw
    raw="$(trim "$raw")"
    raw="${raw// /}"  # remove spaces

    if [[ -z "$raw" ]]; then
      add_log "Empty ports. Please try again."
      continue
    fi

    local -a ports=()
    local ok=1
    IFS=',' read -r -a parts <<<"$raw"
    for part in "${parts[@]}"; do
      if valid_port "$part"; then
        ports+=("$part")
      else
        ok=0
        break
      fi
    done

    if ((ok==0)); then
      add_log "Invalid ports: $raw"
      add_log "Enter comma-separated numbers only, e.g., 80,443,2053"
      continue
    fi

    # Sort and deduplicate
    PORT_LIST=($(printf "%s\n" "${ports[@]}" | awk '!seen[$0]++' | sort -n))
    add_log "Ports accepted: ${PORT_LIST[*]}"
    return 0
  done
}

ensure_iproute_only() {
  add_log "Checking required package: iproute2"
  render

  if command -v ip >/dev/null 2>&1; then
    add_log "iproute2 is already installed."
    return 0
  fi

  add_log "Installing missing package: iproute2"
  render
  if [[ "${DEBUG:-0}" == "1" ]]; then
    apt-get update -y
    apt-get install -y iproute2
  else
    apt-get update -y >/dev/null 2>&1
    apt-get install -y iproute2 >/dev/null 2>&1
  fi
  if [[ $? -eq 0 ]]; then
    add_log "iproute2 installed successfully."
    return 0
  else
    add_log "Failed to install iproute2."
    return 1
  fi
}

ensure_packages() {
  add_log "Checking required packages: iproute2, haproxy"
  render
  local missing=()
  command -v ip >/dev/null 2>&1 || missing+=("iproute2")
  command -v haproxy >/dev/null 2>&1 || missing+=("haproxy")

  if ((${#missing[@]}==0)); then
    add_log "All required packages are installed."
    return 0
  fi

  add_log "Installing missing packages: ${missing[*]}"
  render
  if [[ "${DEBUG:-0}" == "1" ]]; then
    apt-get update -y
    apt-get install -y "${missing[@]}"
  else
    apt-get update -y >/dev/null 2>&1
    apt-get install -y "${missing[@]}" >/dev/null 2>&1
  fi
  if [[ $? -eq 0 ]]; then
    add_log "Packages installed successfully."
    return 0
  else
    add_log "Failed to install packages."
    return 1
  fi
}

systemd_reload() { systemctl daemon-reload >/dev/null 2>&1; }
unit_exists() { [[ -f "/etc/systemd/system/$1" ]]; }
enable_now() { systemctl enable --now "$1" >/dev/null 2>&1; }

show_unit_status_brief() {
  systemctl --no-pager --full status "$1" 2>&1 | sed -n '1,12p'
}

valid_mtu() {
  local m="$1"
  [[ "$m" =~ ^[0-9]+$ ]] || return 1
  ((m>=576 && m<=1600))
}

ensure_mtu_line_in_unit() {
  local name="$1" mtu="$2" file="$3"
  [[ -f "$file" ]] || return 0

  if grep -qE "^ExecStart=/sbin/ip link set ${name} mtu [0-9]+$" "$file"; then
    sed -i.bak -E "s|^(ExecStart=/sbin/ip link set ${name} mtu )[0-9]+$|\1${mtu}|" "$file"
    add_log "Updated MTU line in: $file"
    return 0
  fi

  if grep -qE "^ExecStart=/sbin/ip link set ${name} up$" "$file"; then
    sed -i.bak -E "/^ExecStart=\/sbin\/ip link set ${name} up$/i ExecStart=/sbin/ip link set ${name} mtu ${mtu}" "$file"
    add_log "Inserted MTU line before 'up' in: $file"
    return 0
  fi

  echo "ExecStart=/sbin/ip link set ${name} mtu ${mtu}" >> "$file"
  add_log "Appended MTU line at end of: $file"
}

make_tunnel_service() {
  local name="$1" local_ip="$2" remote_ip="$3" local_tun_ip="$4" key="$5" mtu="${6:-}"
  local unit="${name}.service"
  local path="/etc/systemd/system/${unit}"

  if unit_exists "$unit"; then
    add_log "Service already exists: $unit"
    return 2
  fi

  add_log "Creating service: $path"
  render

  local mtu_line=""
  if [[ -n "$mtu" ]]; then
    mtu_line="ExecStart=/sbin/ip link set ${name} mtu ${mtu}"
  fi

  cat >"$path" <<EOF
[Unit]
Description=GRE Tunnel ${name} to (${remote_ip})
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c "/sbin/ip tunnel del ${name} 2>/dev/null || true"
ExecStart=/sbin/ip tunnel add ${name} mode gre local ${local_ip} remote ${remote_ip} key ${key} nopmtudisc
ExecStart=/sbin/ip addr add ${local_tun_ip}/30 dev ${name}
${mtu_line}
ExecStart=/sbin/ip link set ${name} up
ExecStop=/sbin/ip link set ${name} down
ExecStop=/sbin/ip tunnel del ${name}

[Install]
WantedBy=multi-user.target
EOF

  [[ $? -eq 0 ]] && add_log "Service created: $unit" || return 1
  return 0
}

haproxy_unit_exists() {
  systemctl list-unit-files --no-legend 2>/dev/null | awk '{print $1}' | grep -qx 'haproxy.service'
}

haproxy_write_main_cfg() {
  add_log "Rebuilding /etc/haproxy/haproxy.cfg (no include)"
  render

  rm -f /etc/haproxy/haproxy.cfg >/dev/null 2>&1 || true

  cat >/etc/haproxy/haproxy.cfg <<'EOF'
#HAPROXY-FOR-GRE
global
    log /dev/log local0
    log /dev/log local1 notice
    daemon
    maxconn 200000

defaults
    log global
    mode tcp
    option tcplog
    timeout connect 5s
    timeout client  1m
    timeout server  1m

EOF
}

haproxy_write_tunnel_cfg() {
  local name="$1" target_ip="$2"
  shift 2
  local -a ports=("$@")

  mkdir -p /etc/haproxy/conf.d >/dev/null 2>&1 || true
  local cfg="/etc/haproxy/conf.d/${name}.cfg"

  if [[ -f "$cfg" ]]; then
    add_log "ERROR: ${name}.cfg already exists."
    return 2
  fi

  add_log "Creating HAProxy config: $cfg"
  render

  : >"$cfg" || return 1

  local p
  for p in "${ports[@]}"; do
    cat >>"$cfg" <<EOF
frontend ${name}_fe_${p}
    bind 0.0.0.0:${p}
    default_backend ${name}_be_${p}

backend ${name}_be_${p}
    option tcp-check
    server ${name}_b_${p} ${target_ip}:${p} check

EOF
  done

  return 0
}

haproxy_patch_systemd() {
  local dir="/etc/systemd/system/haproxy.service.d"
  local override="${dir}/override.conf"

  if ! haproxy_unit_exists; then
    add_log "ERROR: haproxy service not found"
    return 1
  fi

  add_log "Patching systemd for haproxy to load /etc/haproxy/conf.d/ (drop-in override)"
  render

  mkdir -p "$dir" >/dev/null 2>&1 || return 1

  cat >"$override" <<'EOF'
[Service]
Environment="CONFIG=/etc/haproxy/haproxy.cfg"
Environment="PIDFILE=/run/haproxy.pid"
Environment="EXTRAOPTS=-S /run/haproxy-master.sock"
ExecStart=
ExecStart=/usr/sbin/haproxy -Ws -f $CONFIG -f /etc/haproxy/conf.d/ -p $PIDFILE $EXTRAOPTS
ExecReload=
ExecReload=/usr/sbin/haproxy -Ws -f $CONFIG -f /etc/haproxy/conf.d/ -c -q $EXTRAOPTS
EOF

  systemctl daemon-reload >/dev/null 2>&1 || true
  return 0
}

haproxy_validate() {
  local tmp_log
  tmp_log="$(mktemp)"
  if haproxy -c -f /etc/haproxy/haproxy.cfg -f /etc/haproxy/conf.d/ >"$tmp_log" 2>&1; then
    add_log "HAProxy config validation passed."
    rm -f "$tmp_log"
    return 0
  else
    add_log "HAProxy config validation FAILED. Errors:"
    while IFS= read -r line; do
      add_log "  $line"
    done <"$tmp_log"
    rm -f "$tmp_log"
    return 1
  fi
}

haproxy_apply_and_show() {
  haproxy_patch_systemd || return 1

  add_log "Enabling HAProxy..."
  render
  if [[ "${DEBUG:-0}" == "1" ]]; then
    systemctl enable --now haproxy
  else
    systemctl enable --now haproxy >/dev/null 2>&1 || true
  fi

  add_log "Restarting HAProxy..."
  render
  if [[ "${DEBUG:-0}" == "1" ]]; then
    systemctl restart haproxy
  else
    systemctl restart haproxy >/dev/null 2>&1 || true
  fi

  render
  echo "---- STATUS (haproxy.service) ----"
  systemctl status haproxy --no-pager 2>&1 | sed -n '1,18p'
  echo "---------------------------------"
}

# =============================================================================
# Improved get_tunnel_names: only returns services with "GRE Tunnel" description
# =============================================================================
get_tunnel_names() {
  local names=()
  while IFS= read -r unit; do
    # Check if the service description contains "GRE Tunnel"
    if systemctl show -p Description "$unit" 2>/dev/null | grep -q "GRE Tunnel"; then
      names+=("${unit%.service}")
    fi
  done < <(systemctl list-unit-files --no-legend 2>/dev/null | awk '{print $1}' | grep '\.service$')
  printf "%s\n" "${names[@]}" | sort -u
}

MENU_SELECTED=-1

menu_select_index() {
  local title="$1"
  local prompt="$2"
  shift 2
  local -a items=("$@")
  local choice=""

  while true; do
    render
    echo "$title"
    echo

    if ((${#items[@]} == 0)); then
      echo "No tunnel found."
      echo
      read -r -p "Press ENTER to go back..." _
      MENU_SELECTED=-1
      return 1
    fi

    local i
    for ((i=0; i<${#items[@]}; i++)); do
      printf "%d) %s\n" $((i+1)) "${items[$i]}"
    done
    echo "0) Back"
    echo

    read -r -e -p "$prompt " choice
    choice="$(trim "$choice")"

    if [[ "$choice" == "0" ]]; then
      MENU_SELECTED=-1
      return 1
    fi

    if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice>=1 && choice<=${#items[@]})); then
      MENU_SELECTED=$((choice-1))
      return 0
    fi

    add_log "Invalid selection: $choice"
  done
}

service_action_menu() {
  local unit="$1"
  local action=""

  while true; do
    render
    echo "Selected: $unit"
    echo
    echo "1) Enable & Start"
    echo "2) Restart"
    echo "3) Stop & Disable"
    echo "4) Status"
    echo "0) Back"
    echo

    read -r -e -p "Select action: " action
    action="$(trim "$action")"

    case "$action" in
      1)
        add_log "Enable & Start: $unit"
        if [[ "${DEBUG:-0}" == "1" ]]; then
          systemctl enable "$unit"
          systemctl start "$unit"
        else
          systemctl enable "$unit" >/dev/null 2>&1 && add_log "Enabled: $unit" || add_log "Enable failed: $unit"
          systemctl start "$unit"  >/dev/null 2>&1 && add_log "Started: $unit" || add_log "Start failed: $unit"
        fi
        ;;
      2)
        add_log "Restart: $unit"
        if [[ "${DEBUG:-0}" == "1" ]]; then
          systemctl restart "$unit"
        else
          systemctl restart "$unit" >/dev/null 2>&1 && add_log "Restarted: $unit" || add_log "Restart failed: $unit"
        fi
        ;;
      3)
        add_log "Stop & Disable: $unit"
        if [[ "${DEBUG:-0}" == "1" ]]; then
          systemctl stop "$unit"
          systemctl disable "$unit"
        else
          systemctl stop "$unit"    >/dev/null 2>&1 && add_log "Stopped: $unit" || add_log "Stop failed: $unit"
          systemctl disable "$unit" >/dev/null 2>&1 && add_log "Disabled: $unit" || add_log "Disable failed: $unit"
        fi
        ;;
      4)
        render
        echo "---- STATUS ($unit) ----"
        systemctl --no-pager --full status "$unit" 2>&1 | sed -n '1,16p'
        echo "------------------------"
        pause_enter
        ;;
      0) return 0 ;;
      *) add_log "Invalid action: $action" ;;
    esac
  done
}

# =============================================================================
# Services Management: only tunnels, HAProxy removed
# =============================================================================
services_management() {
  local sel=""

  while true; do
    render
    echo "Services Management"
    echo
    echo "1) Tunnels"
    echo "0) Back"
    echo
    read -r -e -p "Select: " sel
    sel="$(trim "$sel")"

    case "$sel" in
      1)
        mapfile -t TUNNEL_NAMES < <(get_tunnel_names)
        if menu_select_index "Tunnel Services" "Select tunnel:" "${TUNNEL_NAMES[@]}"; then
          name="${TUNNEL_NAMES[$MENU_SELECTED]}"
          add_log "Tunnel selected: $name"
          service_action_menu "${name}.service"
        fi
        ;;
      0) return 0 ;;
      *) add_log "Invalid selection: $sel" ;;
    esac
  done
}

get_tunnel_local_ip_cidr() {
  local name="$1"
  ip -4 -o addr show dev "$name" 2>/dev/null | awk '{print $4}' | head -n1
}

get_peer_ip_from_local_cidr() {
  local cidr="$1"
  local ip="${cidr%/*}"
  local mask="${cidr#*/}"
  IFS='.' read -r a b c d <<<"$ip"
  local peer_d
  if [[ "$d" == "1" ]]; then
    peer_d="2"
  elif [[ "$d" == "2" ]]; then
    peer_d="1"
  else
    peer_d="2"
  fi
  echo "${a}.${b}.${c}.${peer_d}"
}

haproxy_add_ports_to_tunnel_cfg() {
  local name="$1" target_ip="$2"
  shift 2
  local -a ports=("$@")
  local cfg="/etc/haproxy/conf.d/${name}.cfg"

  if [[ ! -f "$cfg" ]]; then
    add_log "ERROR: Not found: $cfg"
    return 1
  fi

  add_log "Editing HAProxy config: $cfg"
  render

  local p added=0 skipped=0
  for p in "${ports[@]}"; do
    if grep -qE "^frontend[[:space:]]+${name}_fe_${p}\b" "$cfg" 2>/dev/null; then
      add_log "Skip (exists): ${name} port ${p}"
      ((skipped++))
      continue
    fi

    cat >>"$cfg" <<EOF

frontend ${name}_fe_${p}
    bind 0.0.0.0:${p}
    default_backend ${name}_be_${p}

backend ${name}_be_${p}
    option tcp-check
    server ${name}_b_${p} ${target_ip}:${p} check
EOF

    add_log "Added: ${name} port ${p} -> ${target_ip}:${p}"
    ((added++))
  done

  add_log "Done. Added=${added}, Skipped=${skipped}"
  return 0
}

add_tunnel_port() {
  render
  add_log "Selected: add tunnel port"
  render

  mapfile -t TUNNEL_NAMES < <(get_tunnel_names)
  if ! menu_select_index "Add Tunnel Port" "Select tunnel:" "${TUNNEL_NAMES[@]}"; then
    return 0
  fi
  name="${TUNNEL_NAMES[$MENU_SELECTED]}"
  add_log "Tunnel selected: $name"
  render

  local cidr
  cidr="$(get_tunnel_local_ip_cidr "$name")"
  if [[ -z "$cidr" ]]; then
    die_soft "Could not detect IP on $name. Is it up and has an IP?"
    return 0
  fi

  local peer_ip
  peer_ip="$(get_peer_ip_from_local_cidr "$cidr")"
  add_log "Detected: $name local=$cidr | peer=$peer_ip"
  render

  PORT_LIST=()
  ask_ports

  haproxy_add_ports_to_tunnel_cfg "$name" "$peer_ip" "${PORT_LIST[@]}" || { die_soft "Failed editing ${name}.cfg"; return 0; }

  if command -v haproxy >/dev/null 2>&1; then
    if ! haproxy_validate; then
      die_soft "HAProxy config validation failed. Check logs above."
      return 0
    fi
  fi

  if haproxy_unit_exists; then
    add_log "Restarting HAProxy..."
    render
    if [[ "${DEBUG:-0}" == "1" ]]; then
      systemctl restart haproxy
    else
      systemctl restart haproxy >/dev/null 2>&1 || true
    fi
    add_log "HAProxy restarted."
  else
    add_log "WARNING: haproxy.service not found; skipped restart."
  fi

  render
  echo "$name updated."
  echo "Local CIDR : ${cidr}"
  echo "Peer IP    : ${peer_ip}"
  echo "Ports added: ${PORT_LIST[*]}"
  echo
  echo "---- STATUS (haproxy.service) ----"
  systemctl status haproxy --no-pager 2>&1 | sed -n '1,16p'
  echo "---------------------------------"
  pause_enter
}

select_and_set_timezone() {
  local choice tz=""
  while true; do
    render
    echo "WARNING: You need set mutual Time to Iran and Kharej Server"
    echo "select your server clock"
    echo
    echo "1) Germany (Europe/Berlin)"
    echo "2) Turkey (Europe/Istanbul)"
    echo "3) France (Europe/Paris)"
    echo "4) Netherlands (Europe/Amsterdam)"
    echo "5) Finland (Europe/Helsinki)"
    echo "6) England (Europe/London)"
    echo "7) Sweden (Europe/Stockholm)"
    echo "8) Russia (Europe/Moscow)"
    echo "9) USA (America/New_York)"
    echo "10) Canada (America/Toronto)"
    echo "11) UTC (Etc/UTC)"
    echo "0) Skip (no change)"
    echo

    read -r -p "Select: " choice
    choice="$(trim "$choice")"

    case "$choice" in
      1) tz="Europe/Berlin" ;;
      2) tz="Europe/Istanbul" ;;
      3) tz="Europe/Paris" ;;
      4) tz="Europe/Amsterdam" ;;
      5) tz="Europe/Helsinki" ;;
      6) tz="Europe/London" ;;
      7) tz="Europe/Stockholm" ;;
      8) tz="Europe/Moscow" ;;
      9) tz="America/New_York" ;;
      10) tz="America/Toronto" ;;
      11) tz="Etc/UTC" ;;
      0) add_log "Timezone setup skipped."; SELECTED_TZ=""; return 0 ;;
      *) add_log "Invalid selection: $choice"; continue ;;
    esac

    add_log "Setting timezone: $tz"
    render

    if [[ "${DEBUG:-0}" == "1" ]]; then
      timedatectl set-timezone "$tz"
      timedatectl set-ntp true
    else
      timedatectl set-timezone "$tz" >/dev/null 2>&1 || { add_log "ERROR: failed set-timezone"; return 1; }
      timedatectl set-ntp true >/dev/null 2>&1 || { add_log "ERROR: failed set-ntp true"; return 1; }
    fi

    local now
    now="$(TZ="$tz" date '+%Y-%m-%d %H:%M %Z')"
    add_log "Timezone set OK: $tz | Now: $now"
    SELECTED_TZ="$tz"
    return 0
  done
}

# -----------------------------------------------------------------------------
# Create Tunnel (replaces both iran_setup and kharej_setup)
# -----------------------------------------------------------------------------
create_tunnel() {
  local side
  render
  echo "Select side:"
  echo "1) Iran (with HAProxy)"
  echo "2) Kharej (without HAProxy)"
  echo
  read -r -p "Choice [1-2]: " side
  side="$(trim "$side")"
  if [[ "$side" != "1" && "$side" != "2" ]]; then
    add_log "Invalid side selected."
    pause_enter
    return 0
  fi

  local name remote_ip local_ip use_mtu mtu_value base_net
  ask_until_valid "Enter tunnel name (letters/numbers only, e.g., mytunnel):" valid_tunnel_name name

  # Auto-detect local IP
  local_ip=$(ip -4 route get 1 | awk '{print $7; exit}' 2>/dev/null)
  if [[ -z "$local_ip" ]]; then
    local_ip=$(hostname -I | awk '{print $1}')
  fi
  render
  echo "Detected your local IP: $local_ip"
  read -r -p "Is this correct? [Y/n]: " confirm
  confirm="$(trim "$confirm")"
  if [[ "$confirm" =~ ^[Nn] ]]; then
    ask_until_valid "Enter correct local IP:" valid_ipv4 local_ip
  else
    add_log "Local IP confirmed: $local_ip"
  fi

  ask_until_valid "Enter remote IP (the other server):" valid_ipv4 remote_ip

  # Ask for base network (must start with 10 and end with 0)
  ask_until_valid "Enter base network (e.g., 10.20.30.0) [must start with 10 and end with 0]:" valid_base_network base_net

  # Derive tunnel IPs: local gets .1, peer gets .2 (or vice versa based on side)
  IFS='.' read -r a b c d <<<"$base_net"
  if [[ "$side" == "1" ]]; then
    # Iran side: local .1, peer .2
    local_tun_ip="${a}.${b}.${c}.1"
    peer_tun_ip="${a}.${b}.${c}.2"
  else
    # Kharej side: local .2, peer .1
    local_tun_ip="${a}.${b}.${c}.2"
    peer_tun_ip="${a}.${b}.${c}.1"
  fi
  add_log "Tunnel IPs: local=$local_tun_ip/30, peer=$peer_tun_ip"

  local key=$(($(date +%s%N | cut -b1-6) % 10000))  # random key

  local use_mtu="n" MTU_VALUE=""
  while true; do
    render
    read -r -p "Set custom MTU? (y/n): " use_mtu
    use_mtu="$(trim "$use_mtu")"
    case "${use_mtu,,}" in
      y|yes)
        ask_until_valid "Enter custom MTU (576-1600):" valid_mtu MTU_VALUE
        break
        ;;
      n|no|"")
        MTU_VALUE=""
        break
        ;;
      *)
        add_log "Invalid input. Please enter y or n."
        ;;
    esac
  done

  # Install packages if needed
  if [[ "$side" == "1" ]]; then
    ensure_packages || { die_soft "Package installation failed."; return 0; }
  else
    ensure_iproute_only || { die_soft "Package installation failed (iproute2)."; return 0; }
  fi

  # Create systemd service for tunnel
  make_tunnel_service "$name" "$local_ip" "$remote_ip" "$local_tun_ip" "$key" "$MTU_VALUE"
  local rc=$?
  [[ $rc -eq 2 ]] && return 0
  [[ $rc -ne 0 ]] && { die_soft "Failed creating tunnel service."; return 0; }

  add_log "Reloading systemd..."
  systemd_reload

  add_log "Starting ${name}.service..."
  enable_now "${name}.service"

  # If Iran side, configure HAProxy
  if [[ "$side" == "1" ]]; then
    PORT_LIST=()
    ask_ports
    add_log "Writing HAProxy config for $name..."
    haproxy_write_tunnel_cfg "$name" "$peer_tun_ip" "${PORT_LIST[@]}"
    local hrc=$?
    if [[ $hrc -eq 2 ]]; then
      die_soft "${name}.cfg already exists."
      return 0
    elif [[ $hrc -ne 0 ]]; then
      die_soft "Failed writing HAProxy config."
      return 0
    fi

    haproxy_write_main_cfg

    if command -v haproxy >/dev/null 2>&1; then
      if ! haproxy_validate; then
        die_soft "HAProxy config validation failed. Check logs above."
        return 0
      fi
    fi

    haproxy_apply_and_show || { die_soft "Failed applying HAProxy systemd override."; return 0; }

    render
    echo "Tunnel '$name' created (Iran side)."
    echo "Tunnel IPs:"
    echo "  Local tunnel IP : ${local_tun_ip}/30"
    echo "  Peer tunnel IP  : ${peer_tun_ip}"
    echo "HAProxy forwards ports: ${PORT_LIST[*]}"
  else
    render
    echo "Tunnel '$name' created (Kharej side)."
    echo "Tunnel IPs:"
    echo "  Local tunnel IP : ${local_tun_ip}/30"
    echo "  Peer tunnel IP  : ${peer_tun_ip}"
  fi

  echo
  echo "Status:"
  show_unit_status_brief "${name}.service"
  pause_enter
}

# -----------------------------------------------------------------------------
# Uninstall tunnel (clean) with y/n confirmation
# -----------------------------------------------------------------------------
uninstall_clean() {
  mapfile -t TUNNEL_NAMES < <(get_tunnel_names)
  if ! menu_select_index "Uninstall Tunnel" "Select tunnel to uninstall:" "${TUNNEL_NAMES[@]}"; then
    return 0
  fi
  name="${TUNNEL_NAMES[$MENU_SELECTED]}"

  while true; do
    render
    echo "Uninstall Tunnel: $name"
    echo "This will remove:"
    echo "  - /etc/systemd/system/${name}.service"
    echo "  - ALL autostart symlinks (*.wants) for $name"
    echo "  - /etc/haproxy/conf.d/${name}.cfg (if exists)"
    echo "  - GRE interface + routes + neighbors + conntrack sessions (best effort)"
    echo "  - Anti-filter components (cron, dummy service, scripts) if present"
    echo
    echo "Confirm deletion? (y/n)"
    echo
    local confirm=""
    read -r -e -p "Confirm: " confirm
    confirm="$(trim "$confirm")"

    if [[ "$confirm" == "n" || "$confirm" == "N" ]]; then
      add_log "Uninstall cancelled for $name"
      return 0
    fi
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
      break
    fi
    add_log "Please type y or n."
  done

  add_log "Stopping ${name}.service (hard)"
  if systemctl list-units --full --all | grep -q "${name}.service"; then
    if [[ "${DEBUG:-0}" == "1" ]]; then
      systemctl stop "${name}.service"
      systemctl kill -s SIGKILL "${name}.service"
    else
      systemctl stop "${name}.service" >/dev/null 2>&1 || true
      systemctl kill -s SIGKILL "${name}.service" >/dev/null 2>&1 || true
    fi
  else
    add_log "Service not active, skipping stop."
  fi

  add_log "Disabling ${name}.service"
  if [[ "${DEBUG:-0}" == "1" ]]; then
    systemctl disable "${name}.service"
  else
    systemctl disable "${name}.service" >/dev/null 2>&1 || true
  fi
  systemctl reset-failed "${name}.service" >/dev/null 2>&1 || true

  add_log "Removing autostart symlinks (*.wants) for $name"
  for d in /etc/systemd/system/*.wants /etc/systemd/system/*/*.wants; do
    rm -f "$d/${name}.service" >/dev/null 2>&1 || true
  done

  add_log "Flushing routes/addr/neigh/conntrack for $name"
  ip route flush dev "$name" 2>/dev/null || true
  ip addr flush dev "$name" 2>/dev/null || true
  ip link set "$name" down 2>/dev/null || true
  ip tunnel del "$name" 2>/dev/null || true
  ip link del "$name" 2>/dev/null || true
  ip route flush cache 2>/dev/null || true
  ip neigh flush all 2>/dev/null || true

  if command -v conntrack >/dev/null 2>&1; then
    conntrack -D -i "$name" >/dev/null 2>&1 || true
    conntrack -D -o "$name" >/dev/null 2>&1 || true
  fi

  add_log "Removing unit file + drop-ins..."
  rm -f "/etc/systemd/system/${name}.service" >/dev/null 2>&1 || true
  rm -rf "/etc/systemd/system/${name}.service.d" >/dev/null 2>&1 || true

  add_log "Removing HAProxy config for $name (if exists)..."
  rm -f "/etc/haproxy/conf.d/${name}.cfg" >/dev/null 2>&1 || true

  add_log "Reloading systemd..."
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl reset-failed >/dev/null 2>&1 || true
  systemctl daemon-reload >/dev/null 2>&1 || true

  # Remove anti-filter components if present
  add_log "Removing anti-filter components for $name (if any)..."
  crontab -l 2>/dev/null | grep -v "/usr/local/bin/sepehr-restart-${name}.sh" | crontab - 2>/dev/null || true
  rm -f "/usr/local/bin/sepehr-restart-${name}.sh" >/dev/null 2>&1 || true
  rm -f "/usr/local/bin/sepehr-dummy-${name}.sh" >/dev/null 2>&1 || true
  systemctl stop "sepehr-dummy-${name}.service" 2>/dev/null || true
  systemctl disable "sepehr-dummy-${name}.service" 2>/dev/null || true
  rm -f "/etc/systemd/system/sepehr-dummy-${name}.service" >/dev/null 2>&1 || true
  systemctl daemon-reload

  if haproxy_unit_exists; then
    add_log "Validating haproxy config..."
    if command -v haproxy >/dev/null 2>&1; then
      if ! haproxy_validate; then
        add_log "WARNING: haproxy config validation failed after cfg removal (check your remaining cfg files)."
      fi
    fi
    add_log "Restarting haproxy..."
    if [[ "${DEBUG:-0}" == "1" ]]; then
      systemctl restart haproxy
    else
      systemctl restart haproxy >/dev/null 2>&1 || true
    fi
  fi

  add_log "Uninstall completed for $name"
  render
  pause_enter
}

# -----------------------------------------------------------------------------
# Anti-Filter System (Enable) – اصلاح‌شده: استفاده از peer_ip و dummy_port
# -----------------------------------------------------------------------------
setup_antifilter_all() {
    local name remote_ip dummy_port interval
    local unit haproxy_cfg restart_script dummy_script service_file
    local -a TUNNEL_NAMES ports

    mapfile -t TUNNEL_NAMES < <(get_tunnel_names)
    if [[ ${#TUNNEL_NAMES[@]} -eq 0 ]]; then
        add_log "No tunnels found."
        pause_enter
        return 0
    fi

    if ! menu_select_index "Select tunnel for anti-filter setup" "Tunnel name:" "${TUNNEL_NAMES[@]}"; then
        return 0
    fi
    name="${TUNNEL_NAMES[$MENU_SELECTED]}"
    add_log "Tunnel selected: $name"

    unit="/etc/systemd/system/${name}.service"
    if [[ ! -f "$unit" ]]; then
        die_soft "Service file not found: $unit"
        return 0
    fi

    # استخراج remote_ip (فعلاً برای نمایش)
    remote_ip=$(grep -oP 'remote \K[0-9.]+' "$unit" | head -n1)
    if [[ -z "$remote_ip" ]]; then
        die_soft "Could not detect remote IP from unit."
        return 0
    fi
    add_log "Remote IP detected: $remote_ip (for reference only)"

    # محاسبه peer_ip (IP داخلی تونل همتا) با استفاده از توابع موجود
    local cidr peer_ip
    cidr="$(get_tunnel_local_ip_cidr "$name")"
    if [[ -z "$cidr" ]]; then
        die_soft "Could not detect local tunnel IP. Is the tunnel up?"
        return 0
    fi
    peer_ip="$(get_peer_ip_from_local_cidr "$cidr")"
    add_log "Tunnel peer IP: $peer_ip (will be used in HAProxy backend)"

    render
    read -r -p "Enter port for dummy HTTPS traffic (default 443): " dummy_port
    dummy_port=${dummy_port:-443}
    if ! valid_port "$dummy_port"; then
        add_log "Invalid port, using default 443."
        dummy_port=443
    fi

    read -r -p "Enter restart interval in minutes (default 15): " interval
    interval=${interval:-15}
    if ! [[ "$interval" =~ ^[0-9]+$ ]] || ((interval < 1 || interval > 60)); then
        add_log "Invalid interval, using 15 minutes."
        interval=15
    fi

    add_log "Starting anti-filter configuration for $name..."

    # Clean old sepehr scripts for this tunnel (if any)
    crontab -l 2>/dev/null | grep -v "/usr/local/bin/sepehr-restart-${name}.sh" | crontab - 2>/dev/null || true
    rm -f "/usr/local/bin/sepehr-restart-${name}.sh" "/usr/local/bin/sepehr-dummy-${name}.sh" 2>/dev/null || true
    systemctl stop "sepehr-dummy-${name}.service" 2>/dev/null || true
    systemctl disable "sepehr-dummy-${name}.service" 2>/dev/null || true
    rm -f "/etc/systemd/system/sepehr-dummy-${name}.service" 2>/dev/null || true
    systemctl daemon-reload

    # Enhance HAProxy config
    haproxy_cfg="/etc/haproxy/conf.d/${name}.cfg"
    if [[ ! -f "$haproxy_cfg" ]]; then
        die_soft "HAProxy config file for $name not found."
        return 0
    fi

    add_log "Enhancing HAProxy config: $haproxy_cfg"
    cp "$haproxy_cfg" "${haproxy_cfg}.bak.$(date +%s)"

    # Extract ports
    ports=($(grep -oP "^frontend ${name}_fe_\K[0-9]+" "$haproxy_cfg" | sort -n | uniq))
    if [[ ${#ports[@]} -eq 0 ]]; then
        die_soft "No ports found in HAProxy config."
        return 0
    fi
    add_log "Found ports: ${ports[*]}"

    # Rewrite with HTTPS-like settings – استفاده از peer_ip به‌جای remote_ip
    : > "$haproxy_cfg"
    for p in "${ports[@]}"; do
        cat >> "$haproxy_cfg" <<EOF
frontend ${name}_fe_${p}
    bind 0.0.0.0:${p}
    mode tcp
    option tcplog
    tcp-request inspect-delay 5s
    timeout client 60s
    default_backend ${name}_be_${p}

backend ${name}_be_${p}
    mode tcp
    option tcpka
    option tcp-check
    timeout server 60s
    server ${name}_b_${p} ${peer_ip}:${p} check

EOF
    done
    add_log "HAProxy config updated (backend now points to tunnel peer IP)."

    # Add periodic restart cron
    restart_script="/usr/local/bin/sepehr-restart-${name}.sh"
    cat > "$restart_script" <<EOF
#!/bin/bash
systemctl restart ${name}.service
EOF
    chmod +x "$restart_script"
    local cron_line="*/${interval} * * * * $restart_script"
    (crontab -l 2>/dev/null; echo "$cron_line") | crontab -
    add_log "Periodic restart added every ${interval} minutes."

    # Create dummy traffic service (to Google) – استفاده از dummy_port
    dummy_script="/usr/local/bin/sepehr-dummy-${name}.sh"
    cat > "$dummy_script" <<EOF
#!/bin/bash
GOOGLE_HOST="www.google.com"
GOOGLE_PORT=${dummy_port}
while true; do
    GOOGLE_IP=\$(getent ahosts "\$GOOGLE_HOST" | awk '/STREAM/ {print \$1; exit}')
    if [[ -n "\$GOOGLE_IP" ]]; then
        printf "GET / HTTP/1.1\r\nHost: \$GOOGLE_HOST\r\nUser-Agent: Mozilla/5.0\r\nConnection: close\r\n\r\n" \
            | nc -w 3 "\$GOOGLE_IP" "\$GOOGLE_PORT" >/dev/null 2>&1
    fi
    sleep \$((30 + RANDOM % 60))
done
EOF
    chmod +x "$dummy_script"

    service_file="/etc/systemd/system/sepehr-dummy-${name}.service"
    cat > "$service_file" <<EOF
[Unit]
Description=Dummy HTTPS traffic for ${name} (to Google)
After=network.target ${name}.service

[Service]
Type=simple
ExecStart=$dummy_script
Restart=always
User=nobody
Group=nogroup

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now "sepehr-dummy-${name}.service" >/dev/null 2>&1
    add_log "Dummy traffic service started (to Google, port ${dummy_port})."

    # Restart HAProxy
    if command -v haproxy >/dev/null 2>&1; then
        add_log "Restarting HAProxy..."
        if [[ "${DEBUG:-0}" == "1" ]]; then
            systemctl restart haproxy
        else
            systemctl restart haproxy >/dev/null 2>&1 || true
        fi
        add_log "HAProxy restarted."
    fi

    render
    echo "Anti-filter settings for $name applied successfully:"
    echo "  - HAProxy config enhanced (${#ports[@]} ports) – backend now uses tunnel peer IP ($peer_ip)"
    echo "  - Restart cron every ${interval} minutes"
    echo "  - Dummy traffic to Google on port ${dummy_port}"
    pause_enter
}

# -----------------------------------------------------------------------------
# Remove Anti-Filter System
# -----------------------------------------------------------------------------
remove_antifilter() {
    local name="$1"
    add_log "Removing Anti-Filter system for $name..."

    local restart_script="/usr/local/bin/sepehr-restart-${name}.sh"
    local dummy_script="/usr/local/bin/sepehr-dummy-${name}.sh"
    local dummy_service="/etc/systemd/system/sepehr-dummy-${name}.service"

    crontab -l 2>/dev/null | grep -vF "$restart_script" | crontab - 2>/dev/null || true

    if systemctl list-unit-files 2>/dev/null | grep -q "sepehr-dummy-${name}.service"; then
        add_log "Stopping dummy service..."
        systemctl stop "sepehr-dummy-${name}.service" 2>/dev/null || true
        systemctl disable "sepehr-dummy-${name}.service" 2>/dev/null || true
    fi

    add_log "Removing anti-filter files..."
    rm -f "$dummy_service"
    rm -f "$dummy_script"
    rm -f "$restart_script"

    systemctl daemon-reload >/dev/null 2>&1 || true

    if systemctl list-unit-files 2>/dev/null | grep -q haproxy.service; then
        add_log "Restarting HAProxy..."
        systemctl restart haproxy >/dev/null 2>&1 || true
    fi

    add_log "Anti-Filter system fully removed for $name"
    render
    echo "Anti-Filter system for $name successfully removed."
    pause_enter
}

# -----------------------------------------------------------------------------
# Change MTU
# -----------------------------------------------------------------------------
change_mtu() {
  local name mtu
  mapfile -t TUNNEL_NAMES < <(get_tunnel_names)
  if ! menu_select_index "Change MTU" "Select tunnel:" "${TUNNEL_NAMES[@]}"; then
    return 0
  fi
  name="${TUNNEL_NAMES[$MENU_SELECTED]}"

  ask_until_valid "Enter new MTU (576-1600):" valid_mtu mtu

  add_log "Setting MTU on interface $name to $mtu..."
  render
  ip link set "$name" mtu "$mtu" >/dev/null 2>&1 || add_log "WARNING: $name interface not found or not up (will still patch unit)."

  local unit="/etc/systemd/system/${name}.service"
  add_log "Patching unit file: $unit"
  render
  if [[ -f "$unit" ]]; then
    ensure_mtu_line_in_unit "$name" "$mtu" "$unit"
  else
    die_soft "Unit file not found: $unit"
    return 0
  fi

  add_log "Reloading systemd..."
  systemd_reload

  add_log "Restarting ${name}.service..."
  if [[ "${DEBUG:-0}" == "1" ]]; then
    systemctl restart "${name}.service"
  else
    systemctl restart "${name}.service" >/dev/null 2>&1 || add_log "WARNING: restart failed for ${name}.service"
  fi

  add_log "Done: MTU changed to $mtu"
  render
  pause_enter
}

# -----------------------------------------------------------------------------
# Main Menu
# -----------------------------------------------------------------------------
main_menu() {
  local choice=""
  while true; do
    render
    echo -e "\e[38;5;15m[1] 🚀 Create New Tunnel"
    echo "[2] 🔍 Show Active Tunnels"
    echo "[3] ⚙️ Settings"
    echo "[4] 🧹 Uninstall Tunnel"
    echo "[5] ➕ Add Port to Tunnel"
    echo "[6] 🛡️ Anti-Filter System"
    echo "[7] 📦 Change MTU"
    echo "[0] ❌ Exit\e[0m"
    echo
    read -r -e -p "Select option: " choice
    choice="$(trim "$choice")"

    case "$choice" in
      1) add_log "Selected: Create New Tunnel"; create_tunnel ;;
      2) add_log "Selected: Show Active Tunnels"; services_management ;;
      3) add_log "Selected: Settings"; select_and_set_timezone ;;
      4) add_log "Selected: Uninstall Tunnel"; uninstall_clean ;;
      5) add_log "Selected: Add Port to Tunnel"; add_tunnel_port ;;
      6) 
        render
        echo "Anti-Filter System"
        echo "1) Enable Anti-Filter System"
        echo "2) Remove Anti-Filter System"
        echo
        read -r -p "Select option [1-2]: " af_choice
        af_choice="$(trim "$af_choice")"
        case "$af_choice" in
          1)
            add_log "Selected: Enable Anti-Filter"
            setup_antifilter_all
            ;;
          2)
            add_log "Selected: Remove Anti-Filter"
            mapfile -t TUNNEL_NAMES < <(get_tunnel_names)
            if [[ ${#TUNNEL_NAMES[@]} -eq 0 ]]; then
                add_log "No tunnels found."
                pause_enter
                continue
            fi
            if menu_select_index "Remove Anti-Filter System" "Select tunnel:" "${TUNNEL_NAMES[@]}"; then
                name="${TUNNEL_NAMES[$MENU_SELECTED]}"
                remove_antifilter "$name"
            fi
            ;;
          *)
            add_log "Invalid option: $af_choice"
            pause_enter
            ;;
        esac
        ;;
      7) add_log "Selected: Change MTU"; change_mtu ;;
      0) add_log "Bye!"; render; exit 0 ;;
      *) add_log "Invalid option: $choice" ;;
    esac
  done
}

ensure_root "$@"
add_log "Truma Tunnel Manager started (Debug Version)"
main_menu