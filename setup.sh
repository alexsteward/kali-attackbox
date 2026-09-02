#!/usr/bin/env bash
###############################################################################
# setup.sh — Kali attack box provisioner
# Turns a fresh Kali Linux install into a ready-to-use pentest workstation:
# tooling, audit logging, remote access, and desktop quality-of-life.
#
#   sudo ./setup.sh                 # full build
#   sudo ./setup.sh --only offensive
#   sudo ./setup.sh --skip burp,remote
#   sudo ./setup.sh --plain         # no animation (dumb terminals / piping)
#
# Resilient: a failed module is logged and the run continues; a live status
# board shows progress and a summary + attention list prints at the end.
# Full detail log: /var/log/kali-attackbox-setup.log
###############################################################################
set -uo pipefail

LOG="/var/log/kali-attackbox-setup.log"
NOTES="$(mktemp)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export DEBIAN_FRONTEND=noninteractive
: > "$LOG"

MODULES=(base shell dev docker networking offensive wintools audit desktop remote burp veracrypt vm)
declare -A LABELS=(
  [base]="System base + upgrade" [shell]="Shell + aliases"
  [dev]="Dev toolchain" [docker]="Docker engine"
  [networking]="Network utilities" [offensive]="Offensive arsenal"
  [wintools]="Windows target tools" [audit]="Sudo I/O audit log" [desktop]="Desktop tweaks"
  [remote]="Remote access (xrdp)" [burp]="Burp Suite"
  [veracrypt]="VeraCrypt" [vm]="VM guest agents"
)
declare -A RESULT

# ---------------------------------------------------------------------------
# colours + note sink (module output goes to $LOG; these notes drive the UI)
# ---------------------------------------------------------------------------
e(){ printf '\e[%sm' "$1"; }
C_RST=$'\e[0m'; C_DIM=$'\e[90m'; C_GRN=$'\e[32m'; C_RED=$'\e[31m'
C_YEL=$'\e[33m'; C_CYN=$'\e[36m'; C_WHT=$'\e[97m'; C_BLU=$'\e[38;5;39m'
ok(){   printf 'OK|%s\n'   "$*" >>"$NOTES"; }
warn(){ printf 'WARN|%s\n' "$*" >>"$NOTES"; }
err(){  printf 'ERR|%s\n'  "$*" >>"$NOTES"; }
log(){  printf 'INFO|%s\n' "$*" >>"$NOTES"; }

# apt install that never aborts the run; records anything it couldn't get
apt_install(){
  local failed=()
  if ! apt-get install -y --no-install-recommends "$@" >>"$LOG" 2>&1; then
    for p in "$@"; do
      apt-get install -y --no-install-recommends "$p" >>"$LOG" 2>&1 || failed+=("$p")
    done
  fi
  [ ${#failed[@]} -gt 0 ] && warn "could not install: ${failed[*]}" || true
}

fmt(){ local s=$1; printf '%02d:%02d' $((s/60)) $((s%60)); }

# ===========================================================================
# UI
# ===========================================================================
UI=1
banner(){
  [ "$UI" = 1 ] || { echo "== Kali Attack Box Setup =="; return; }
  local g=(238 240 242 244 246 250 253 255)
  clear 2>/dev/null || true
  local art=(
"     █████╗ ████████╗████████╗ █████╗  ██████╗██╗  ██╗"
"    ██╔══██╗╚══██╔══╝╚══██╔══╝██╔══██╗██╔════╝██║ ██╔╝"
"    ███████║   ██║      ██║   ███████║██║     █████╔╝ "
"    ██╔══██║   ██║      ██║   ██╔══██║██║     ██╔═██╗ "
"    ██║  ██║   ██║      ██║   ██║  ██║╚██████╗██║  ██╗"
"    ╚═╝  ╚═╝   ╚═╝      ╚═╝   ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝"
  )
  echo
  local i=0
  for line in "${art[@]}"; do
    printf '  \e[38;5;%sm%s\e[0m\n' "${g[i]}" "$line"; i=$((i+1))
  done
  printf '  %s┃%s %sKALI ATTACK BOX%s  %s· automated setup ·%s\n' \
    "$C_BLU" "$C_RST" "$C_WHT" "$C_RST" "$C_DIM" "$C_RST"
  printf '  %s%s%s\n\n' "$C_DIM" "────────────────────────────────────────────────" "$C_RST"
  printf '   %starget%s  %s@%s        %sdate%s  %s\n' \
    "$C_DIM" "$C_RST" "$TARGET_USER" "$(hostname)" "$C_DIM" "$C_RST" "$(date '+%Y-%m-%d %H:%M')"
  printf '   %slog%s     %s\n\n' "$C_DIM" "$C_RST" "$LOG"
}

# run one module (backgrounded, animated) --------------------------------------
run_one(){
  local m="$1" idx="$2" total="$3"
  local label="${LABELS[$m]:-$m}"
  local rcfile; rcfile="$(mktemp)"
  local start=$SECONDS
  ( "mod_${m}" >>"$LOG" 2>&1; echo $? >"$rcfile" ) &
  local pid=$! frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏) fi=0
  local cols; cols=$(tput cols 2>/dev/null || echo 80)
  if [ "$UI" = 1 ]; then
    tput civis 2>/dev/null || true
    while ! [ -s "$rcfile" ]; do
      # live sub-line: latest activity from the log (so you see it working)
      local sub; sub="$(tail -n1 "$LOG" 2>/dev/null | tr -d '\r' | tr -dc '[:print:]')"
      sub="${sub:0:$((cols-8))}"
      printf '\r\e[K  %s%s%s  %s[%02d/%02d]%s  %-24s %s%s%s\n' \
        "$C_CYN" "${frames[fi%10]}" "$C_RST" "$C_DIM" "$idx" "$total" "$C_RST" \
        "$label" "$C_DIM" "$(fmt $((SECONDS-start)))" "$C_RST"
      printf '\e[K     %s↳ %s%s\e[1A\r' "$C_DIM" "$sub" "$C_RST"
      fi=$((fi+1)); sleep 0.15
    done
    tput cnorm 2>/dev/null || true
    printf '\r\e[K\n\e[K\e[1A\r'          # clear spinner line + sub-line
  else
    printf '  .. [%02d/%02d] %s\n' "$idx" "$total" "$label"
  fi
  wait "$pid" 2>/dev/null
  local rc; rc="$(cat "$rcfile" 2>/dev/null || echo 1)"; rm -f "$rcfile"
  local dur=$((SECONDS-start))
  if [ "$rc" = 0 ]; then
    RESULT[$m]=OK
    printf '  %s✔%s  %s[%02d/%02d]%s  %-24s %s%s%s\n' \
      "$C_GRN" "$C_RST" "$C_DIM" "$idx" "$total" "$C_RST" "$label" "$C_DIM" "$(fmt $dur)" "$C_RST"
  else
    RESULT[$m]=FAIL
    printf '  %s✗%s  %s[%02d/%02d]%s  %-24s %s%s  see log%s\n' \
      "$C_RED" "$C_RST" "$C_DIM" "$idx" "$total" "$C_RST" "$label" "$C_RED" "$(fmt $dur)" "$C_RST"
  fi
}

summary(){
  local okc=0 failc=0
  for m in "${MODULES[@]}"; do [ -n "${RESULT[$m]:-}" ] || continue
    [ "${RESULT[$m]}" = OK ] && okc=$((okc+1)) || failc=$((failc+1)); done
  local total=$((okc+failc)) bar="" n=24 filled
  [ "$total" -gt 0 ] && filled=$(( okc*n/total )) || filled=0
  local j=0; while [ $j -lt $n ]; do
    [ $j -lt $filled ] && bar+="█" || bar+="░"; j=$((j+1)); done
  echo
  printf '  %s%s%s\n' "$C_DIM" "────────────────────────────────────────────────" "$C_RST"
  printf '  %sRESULT%s  %s%s%s  %s%d ok%s  %s%d failed%s\n' \
    "$C_WHT" "$C_RST" "$C_GRN" "$bar" "$C_RST" "$C_GRN" "$okc" "$C_RST" \
    "$( [ $failc -gt 0 ] && echo "$C_RED" || echo "$C_DIM")" "$failc" "$C_RST"

  # attention list (warnings + errors captured during the run)
  if grep -qE '^(WARN|ERR)\|' "$NOTES" 2>/dev/null; then
    echo; printf '  %s⚠ needs attention%s\n' "$C_YEL" "$C_RST"
    grep -E '^ERR\|'  "$NOTES" | sed "s/^ERR|/    ${C_RED}•${C_RST} /"
    grep -E '^WARN\|' "$NOTES" | sed "s/^WARN|/    ${C_YEL}•${C_RST} /"
  fi
  # useful notes (urls/creds/paths)
  if grep -qE '^INFO\|' "$NOTES" 2>/dev/null; then
    echo; printf '  %sℹ notes%s\n' "$C_CYN" "$C_RST"
    grep -E '^INFO\|' "$NOTES" | sed "s/^INFO|/    ${C_DIM}-${C_RST} /"
  fi
  echo
  printf '  %sfull log:%s %s\n' "$C_DIM" "$C_RST" "$LOG"
  printf '  %sreboot recommended (docker group + guest agents apply on next login)%s\n\n' "$C_DIM" "$C_RST"
  # plain-text copy of the summary into the log
  { echo "=== SUMMARY ==="; for m in "${MODULES[@]}"; do
      [ -n "${RESULT[$m]:-}" ] && echo "$m = ${RESULT[$m]}"; done; } >>"$LOG"
}

# ===========================================================================
# preflight
# ===========================================================================
[ "$EUID" -eq 0 ] || { echo "Run with sudo: sudo ./setup.sh"; exit 1; }
command -v apt-get >/dev/null || { echo "apt not found - this script is for Kali/Debian."; exit 1; }
[ -t 1 ] || UI=0

TARGET_USER="${SUDO_USER:-}"
{ [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = "root" ]; } && TARGET_USER="$(id -nu 1000 2>/dev/null || echo kali)"
id "$TARGET_USER" >/dev/null 2>&1 || { echo "Target user '$TARGET_USER' not found."; exit 1; }
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
as_user(){ sudo -u "$TARGET_USER" -H "$@"; }

ONLY=""; SKIP=""
while [ $# -gt 0 ]; do case "$1" in
  --only) ONLY="$2"; shift 2;;
  --skip) SKIP="$2"; shift 2;;
  --plain) UI=0; shift;;
  *) echo "unknown arg: $1"; exit 1;;
esac; done
trap 'tput cnorm 2>/dev/null || true' EXIT

# ===========================================================================
# MODULES
# ===========================================================================
mod_base(){
  apt-get update >>"$LOG" 2>&1 || return 1
  apt-get -y full-upgrade >>"$LOG" 2>&1 || warn "full-upgrade had issues"
  apt_install build-essential pkg-config git curl wget ca-certificates gnupg \
              apt-transport-https software-properties-common jq nano vim tmux powerline unzip
  return 0
}

mod_shell(){
  # quality-of-life aliases + env, hooked into both zsh (Kali default) and bash
  cat > /etc/profile.d/attackbox-aliases.sh <<'EOF'
alias ll='ls -l'; alias la='ls -A'; alias l='ls -CF'
alias lr='ls -Altr'; alias lt='ls -Alt'; alias vi='vim'
alias cmc='cal `date +%b\ %Y`'; alias nmc='cal `date -d "next month" +%b\ %Y`'
alias tmc='cmc && nmc'; alias cyc='cal -y `date +%Y`'
mkd_(){ mkdir -p "$@" && cd "$_"; }
EOF
  chmod 0755 /etc/profile.d/attackbox-aliases.sh
  # bash hook
  if ! grep -q "ATTACK BOX" /etc/bash.bashrc 2>/dev/null; then
    cat >> /etc/bash.bashrc <<'EOF'

# >>> ATTACK BOX >>>
if [[ $- == *i* ]]; then
    [ -r /etc/profile.d/attackbox-aliases.sh ] && . /etc/profile.d/attackbox-aliases.sh
    export EDITOR=vim
    export PATH="${PATH}:${HOME}/.local/bin"
fi
# <<< ATTACK BOX <<<
EOF
    ok "aliases hooked into bash"
  fi
  # zsh hook — Kali's default shell
  mkdir -p /etc/zsh
  if ! grep -qs "ATTACK BOX" /etc/zsh/zshrc 2>/dev/null; then
    cat >> /etc/zsh/zshrc <<'EOF'

# >>> ATTACK BOX >>>
if [[ -o interactive ]]; then
    [ -r /etc/profile.d/attackbox-aliases.sh ] && source /etc/profile.d/attackbox-aliases.sh
    export EDITOR=vim
    export PATH="${PATH}:${HOME}/.local/bin"
fi
# <<< ATTACK BOX <<<
EOF
    ok "aliases hooked into zsh"
  fi
  return 0
}

mod_dev(){
  apt_install golang-go pipx jq
  # Microsoft repo → PowerShell + .NET SDK (not in Kali's own repos)
  if [ ! -f /etc/apt/sources.list.d/microsoft-prod.list ]; then
    ( curl -fsSL https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb -o /tmp/ms.deb \
      && dpkg -i /tmp/ms.deb && apt-get update ) >>"$LOG" 2>&1 || warn "Microsoft repo add failed (dotnet/pwsh may be skipped)"
  fi
  apt_install dotnet-sdk-8.0 powershell
  # python tooling via pipx (Kali is PEP-668 externally-managed; no python3-pipenv pkg)
  as_user pipx ensurepath >>"$LOG" 2>&1 || true
  for t in poetry pipenv ansible-runner; do
    as_user pipx install "$t" >>"$LOG" 2>&1 && ok "pipx: $t" || warn "pipx $t failed"
  done
  # Sublime (best-effort)
  if ! command -v subl >/dev/null; then
    ( curl -fsSL https://download.sublimetext.com/sublimehq-pub.gpg | gpg --dearmor -o /usr/share/keyrings/sublimehq.gpg \
      && echo "deb [signed-by=/usr/share/keyrings/sublimehq.gpg] https://download.sublimetext.com/ apt/stable/" \
         > /etc/apt/sources.list.d/sublime-text.list \
      && apt-get update && apt-get install -y sublime-text ) >>"$LOG" 2>&1 \
      && ok "Sublime Text installed" || warn "Sublime install skipped"
  fi
  # Chrome (best-effort; Chromium is the fallback)
  if ! command -v google-chrome >/dev/null; then
    ( curl -fsSL https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -o /tmp/chrome.deb \
      && apt-get install -y /tmp/chrome.deb ) >>"$LOG" 2>&1 \
      && ok "Google Chrome installed" || { warn "Chrome skipped - installing Chromium"; apt_install chromium; }
  fi
  return 0
}

mod_docker(){
  apt_install docker.io docker-compose
  systemctl enable --now docker >>"$LOG" 2>&1 || warn "could not enable docker"
  usermod -aG docker "$TARGET_USER" && ok "$TARGET_USER added to docker group (re-login to apply)"
  return 0
}

mod_networking(){
  apt_install nmap masscan zmap sshuttle curl openssh-server dnsutils net-tools \
              rsync squid htop iotop iftop netcat-traditional freetds-bin proxychains4
  systemctl enable ssh >>"$LOG" 2>&1 || true
  sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
  if grep -q '^PasswordAuthentication' /etc/ssh/sshd_config; then
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
  else echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config; fi
  systemctl restart ssh >>"$LOG" 2>&1 || warn "sshd restart failed"
  if [ -d /etc/squid ]; then
    cp /etc/squid/squid.conf /etc/squid/squid.conf.bak 2>/dev/null || true
    cat > /etc/squid/squid.conf <<'EOF'
acl localnet src 10.0.0.0/8
acl localnet src 172.16.0.0/12
acl localnet src 192.168.0.0/16
acl SSL_ports port 443
acl Safe_ports port 80 21 443 70 210 1025-65535 280 488 591 777
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
http_access allow localhost manager
http_access deny manager
http_access allow localnet
http_access allow localhost
http_access deny all
http_port 3128
coredump_dir /var/spool/squid
EOF
    systemctl enable squid >>"$LOG" 2>&1 || warn "could not enable squid"
    ok "Squid proxy on :3128 (LAN allowed)"
  fi
  return 0
}

mod_offensive(){
  # Kali ships most of these; ensure the key set + fill gaps.
  apt_install hashcat john hydra ffuf sqlmap wpscan nuclei seclists wordlists \
              responder mitm6 crackmapexec netexec impacket-scripts \
              enum4linux enum4linux-ng nbtscan onesixtyone snmp smbclient ldap-utils \
              socat chisel evil-winrm exiftool ruby gowitness python3-pypykatz \
              bloodhound neo4j
  [ -f /usr/share/wordlists/rockyou.txt.gz ] && gunzip -kf /usr/share/wordlists/rockyou.txt.gz 2>/dev/null || true
  as_user pipx install password-stretcher >>"$LOG" 2>&1 || warn "password-stretcher skipped"
  as_user pipx install bbot >>"$LOG" 2>&1 && ok "pipx: bbot" || warn "bbot skipped"
  as_user pipx install bloodhound >>"$LOG" 2>&1 && ok "pipx: bloodhound-python (Linux collector)" || warn "bloodhound-python skipped"
  if ! command -v gowitness >/dev/null; then
    as_user env GOBIN=/usr/local/bin go install github.com/sensepost/gowitness@latest >>"$LOG" 2>&1 \
      && ok "gowitness (go) installed" || warn "gowitness skipped"
  fi
  if ! command -v kerbrute >/dev/null; then
    as_user env GOBIN=/usr/local/bin go install github.com/ropnop/kerbrute@latest >>"$LOG" 2>&1 \
      && ok "kerbrute installed" || warn "kerbrute skipped"
  fi
  if ! command -v chisel >/dev/null; then    # go fallback if apt didn't provide it
    as_user env GOBIN=/usr/local/bin go install github.com/jpillora/chisel@latest >>"$LOG" 2>&1 \
      && ok "chisel (go) installed" || warn "chisel skipped"
  fi
  # Neo4j service for BloodHound (Kali-packaged, not dockerized - avoids port clash)
  if systemctl list-unit-files 2>/dev/null | grep -q '^neo4j'; then
    systemctl enable neo4j >>"$LOG" 2>&1 || true
    log "BloodHound: launch from the app menu. Neo4j DB = service 'neo4j' (http://localhost:7474, default neo4j/neo4j - set pw on first login)"
  fi
  # Useful public repos into ~/git (impacket also via apt; seclists at /usr/share)
  as_user mkdir -p "$TARGET_HOME/git"
  local names=(impacket petitpotam pre2k windapsearch)
  local urls=(https://github.com/fortra/impacket https://github.com/topotam/PetitPotam https://github.com/garrettfoster13/pre2k https://github.com/ropnop/windapsearch)
  local k=0
  for name in "${names[@]}"; do
    local d="$TARGET_HOME/git/$name"
    if [ ! -d "$d/.git" ]; then
      as_user git clone --depth 1 "${urls[k]}" "$d" >>"$LOG" 2>&1 && ok "cloned $name" || warn "clone $name failed"
    fi
    k=$((k+1))
  done
  # dnscat2 (DNS tunnelling) - clone + build the client
  if [ ! -d "$TARGET_HOME/git/dnscat2/.git" ]; then
    if as_user git clone --depth 1 https://github.com/iagox86/dnscat2 "$TARGET_HOME/git/dnscat2" >>"$LOG" 2>&1; then
      as_user make -C "$TARGET_HOME/git/dnscat2/client" >>"$LOG" 2>&1 \
        && ok "dnscat2 client built (~/git/dnscat2/client/dnscat)" || warn "dnscat2 cloned; client build failed"
    else warn "dnscat2 clone failed"; fi
  fi
  return 0
}

mod_wintools(){
  # Stage Windows target-side tools into ~/tools/windows for use during AUTHORIZED
  # engagements. Sources are official only. These are NOT executed on the box.
  local WT="$TARGET_HOME/tools/windows"
  as_user mkdir -p "$WT"

  # PowerView (PowerSploit) — ready-to-use PowerShell
  if as_user bash -c "curl -fsSL https://raw.githubusercontent.com/PowerShellMafia/PowerSploit/master/Recon/PowerView.ps1 -o '$WT/PowerView.ps1'" >>"$LOG" 2>&1; then
    ok "staged PowerView.ps1"; else warn "PowerView download failed"; fi

  # DomainPasswordSpray — ready-to-use PowerShell
  if [ ! -d "$WT/DomainPasswordSpray/.git" ]; then
    as_user git clone --depth 1 https://github.com/dafthack/DomainPasswordSpray "$WT/DomainPasswordSpray" >>"$LOG" 2>&1 \
      && ok "staged DomainPasswordSpray" || warn "DomainPasswordSpray clone failed"
  fi

  # Rubeus — source (GhostPack ships no official binaries; compile with .NET)
  if [ ! -d "$WT/Rubeus/.git" ]; then
    as_user git clone --depth 1 https://github.com/GhostPack/Rubeus "$WT/Rubeus" >>"$LOG" 2>&1 \
      && ok "staged Rubeus source (compile on Windows/.NET)" || warn "Rubeus clone failed"
  fi

  # Mimikatz — official release zip
  local mz; mz="$(curl -fsSL https://api.github.com/repos/gentilkiwi/mimikatz/releases/latest 2>>"$LOG" | grep -oP 'https://[^"]*mimikatz_trunk\.zip' | head -1)"
  if [ -n "$mz" ]; then
    as_user bash -c "curl -fsSL '$mz' -o '$WT/mimikatz.zip' && unzip -o '$WT/mimikatz.zip' -d '$WT/mimikatz' >/dev/null && rm -f '$WT/mimikatz.zip'" >>"$LOG" 2>&1 \
      && ok "staged mimikatz (official release)" || warn "mimikatz download failed"
  else warn "mimikatz release URL not found"; fi

  # SharpHound — official collector release
  local sh; sh="$(curl -fsSL https://api.github.com/repos/BloodHoundAD/SharpHound/releases/latest 2>>"$LOG" | grep -oP 'https://[^"]*SharpHound[^"]*\.zip' | grep -vi debug | head -1)"
  if [ -n "$sh" ]; then
    as_user bash -c "curl -fsSL '$sh' -o '$WT/sharphound.zip' && unzip -o '$WT/sharphound.zip' -d '$WT/SharpHound' >/dev/null && rm -f '$WT/sharphound.zip'" >>"$LOG" 2>&1 \
      && ok "staged SharpHound (official collector)" || warn "SharpHound download failed"
  else warn "SharpHound release URL not found"; fi

  # Sysinternals PsExec — Microsoft official
  if as_user bash -c "curl -fsSL https://download.sysinternals.com/files/PSTools.zip -o '$WT/PSTools.zip' && unzip -o '$WT/PSTools.zip' -d '$WT/PSTools' >/dev/null && rm -f '$WT/PSTools.zip'" >>"$LOG" 2>&1; then
    ok "staged Sysinternals PsExec"; else warn "PsExec download failed"; fi

  log "Windows tools staged in $WT (for authorized engagement use)"
  return 0
}

mod_audit(){
  cat > /tmp/10-sudo-io <<'EOF'
Defaults log_output
Defaults log_input
Defaults!/usr/bin/sudoreplay !log_output
Defaults!/usr/local/bin/sudoreplay !log_output
Defaults!REBOOT !log_output
Defaults maxseq = 100000
EOF
  if visudo -cf /tmp/10-sudo-io >/dev/null 2>&1; then
    install -m 0440 -o root -g root /tmp/10-sudo-io /etc/sudoers.d/10-sudo-io
    ok "sudo I/O logging → /var/log/sudo-io"
    rm -f /tmp/10-sudo-io; return 0
  fi
  err "sudoers validation failed; audit not installed"; rm -f /tmp/10-sudo-io; return 1
}

mod_desktop(){
  as_user bash -c '
    command -v xfconf-query >/dev/null || exit 0
    xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/inactivity-on-ac -n -t uint -s 0 2>/dev/null
    xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/blank-on-ac -n -t int -s 0 2>/dev/null
    xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/dpms-enabled -n -t bool -s false 2>/dev/null
    xfconf-query -c xfce4-screensaver -p /lock/enabled -n -t bool -s false 2>/dev/null
  ' >>"$LOG" 2>&1 || true
  [ -f /etc/xdg/autostart/light-locker.desktop ] && \
    sed -i '/^Hidden/d; $aHidden=true' /etc/xdg/autostart/light-locker.desktop 2>/dev/null || true
  ok "sleep/screen-lock disabled (best-effort)"
  return 0
}

mod_remote(){
  apt_install xrdp
  adduser xrdp ssl-cert >>"$LOG" 2>&1 || true
  echo "startxfce4" > "$TARGET_HOME/.xsession"
  chown "$TARGET_USER":"$TARGET_USER" "$TARGET_HOME/.xsession"
  systemctl enable --now xrdp >>"$LOG" 2>&1 || { err "xrdp enable failed"; return 1; }
  ok "xrdp on tcp/3389 (XFCE session)"
  return 0
}

mod_burp(){
  apt_install burpsuite
  ok "Burp Suite Community installed (apt)"
  if [ ! -x /opt/BurpSuitePro/BurpSuitePro ]; then
    if curl -fsSL "https://portswigger.net/burp/releases/download?product=pro&type=Linux" -o /tmp/burp-pro.sh 2>>"$LOG"; then
      cat > /tmp/burp.varfile <<'EOF'
sys.adminRights$Boolean=true
sys.installationDir=/opt/BurpSuitePro
sys.symlinkDir=/usr/local/bin
sys.programGroupDisabled$Boolean=true
EOF
      bash /tmp/burp-pro.sh -q -varfile /tmp/burp.varfile >>"$LOG" 2>&1 \
        && ok "Burp Pro → /opt/BurpSuitePro (activate license in GUI)" \
        || warn "Burp Pro silent install failed - Community is available"
    else warn "Burp Pro download failed - Community is available"; fi
  fi
  return 0
}

mod_veracrypt(){
  command -v veracrypt >/dev/null && { ok "veracrypt already present"; return 0; }
  # Not in Kali repos - pull the official Debian .deb (bump VER when a new release drops)
  local VER="1.26.24"
  for base in "Debian-12" "Debian-11"; do
    local url="https://launchpad.net/veracrypt/trunk/${VER}/+download/veracrypt-${VER}-${base}-amd64.deb"
    if curl -fsSL "$url" -o /tmp/veracrypt.deb 2>>"$LOG" && [ -s /tmp/veracrypt.deb ]; then
      if apt-get install -y /tmp/veracrypt.deb >>"$LOG" 2>&1; then
        ok "VeraCrypt ${VER} installed"; rm -f /tmp/veracrypt.deb; return 0
      fi
    fi
  done
  err "VeraCrypt auto-install failed - grab the .deb from https://veracrypt.io/en/Downloads.html"
  return 1
}

mod_vm(){
  local virt; virt="$(systemd-detect-virt 2>/dev/null || echo none)"
  case "$virt" in
    kvm|qemu) apt_install qemu-guest-agent spice-vdagent
              systemctl enable --now qemu-guest-agent >>"$LOG" 2>&1 || true
              ok "QEMU/KVM guest agents installed";;
    vmware)   apt_install open-vm-tools open-vm-tools-desktop
              systemctl enable --now open-vm-tools >>"$LOG" 2>&1 || true
              ok "VMware guest tools installed";;
    oracle)   apt_install virtualbox-guest-x11 virtualbox-guest-utils
              ok "VirtualBox guest additions installed";;
    none)     log "bare metal - no guest agents needed";;
    *)        log "hypervisor '$virt' - no specific agent";;
  esac
  return 0
}

# ===========================================================================
# run
# ===========================================================================
banner
RUN=()
for m in "${MODULES[@]}"; do
  [ -n "$ONLY" ] && [[ ",$ONLY," != *",$m,"* ]] && continue
  [ -n "$SKIP" ] && [[ ",$SKIP," == *",$m,"* ]] && continue
  RUN+=("$m")
done
total=${#RUN[@]}; idx=0
for m in "${RUN[@]}"; do idx=$((idx+1)); run_one "$m" "$idx" "$total"; done
summary
rm -f "$NOTES"
