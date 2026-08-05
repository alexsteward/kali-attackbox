#!/usr/bin/env bash
# portscan.sh — two-stage nmap:
#   stage 1: full TCP port sweep (-p-) to find open ports fast
#   stage 2: -sV -sC against ONLY the ports stage 1 found
#
# Usage:
#   sudo ./portscan.sh <target> [more targets...]
#   sudo RATE=5000 ./portscan.sh 10.10.10.5        # faster sweep
#   sudo OUTDIR=scans ./portscan.sh 10.10.10.5     # custom output dir
#   sudo UDP=1 ./portscan.sh 10.10.10.5            # also scan top-100 UDP ports
#
# Run with sudo so stage 1 uses a fast SYN scan (-sS). Output (normal + XML +
# greppable) is saved per target under $OUTDIR.
set -uo pipefail

[ $# -ge 1 ] || { echo "usage: $0 <target> [more targets...]"; exit 1; }

RATE="${RATE:-1000}"                          # packets/sec for the sweep
OUTDIR="${OUTDIR:-nmap-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUTDIR"

for target in "$@"; do
  safe="${target//[^A-Za-z0-9._-]/_}"         # filesystem-safe name
  base="$OUTDIR/$safe"

  echo "[*] $target — stage 1: sweeping all 65535 TCP ports (rate ${RATE})"
  nmap -p- --min-rate="$RATE" -T4 -Pn \
       -oG "${base}-allports.gnmap" -oN "${base}-allports.txt" "$target" >/dev/null

  ports="$(grep -hoP '\d+/open' "${base}-allports.gnmap" 2>/dev/null | cut -d/ -f1 | sort -n -u | paste -sd, -)"
  if [ -z "$ports" ]; then
    echo "[!] $target — no open TCP ports found; skipping stage 2"
    continue
  fi
  echo "[+] $target — open ports: $ports"

  echo "[*] $target — stage 2: service + default-script scan (-sV -sC)"
  nmap -sV -sC -p"$ports" -Pn \
       -oN "${base}-services.txt" -oX "${base}-services.xml" "$target" | tee "${base}-services.console.txt"

  if [ "${UDP:-0}" = 1 ]; then
    echo "[*] $target — stage 3 (optional): top-100 UDP ports"
    nmap -sU --top-ports 100 -Pn \
         -oN "${base}-udp.txt" -oG "${base}-udp.gnmap" "$target" | tee "${base}-udp.console.txt"
  fi

  echo "[+] $target — done → $OUTDIR/${safe}-services.txt"
  echo
done

echo "[*] all targets complete. results in: $OUTDIR/"
