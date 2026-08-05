# Kali Attack Box Setup

A single, resilient script that turns a **fresh Kali Linux install** into a
ready-to-use penetration-testing workstation — tooling, audit logging, remote
access, and desktop quality-of-life — with a clean live progress UI.

> ⚠️ **Authorized use only.** This installs offensive security tooling. Use it
> only on systems and networks you own or are explicitly authorized to test.
> You are responsible for complying with all applicable laws.

---

## Table of contents

- [What it does](#what-it-does)
- [Prerequisites](#prerequisites)
- [Quick start](#quick-start)
- [Detailed setup](#detailed-setup)
- [Command-line flags](#command-line-flags)
- [Modules](#modules)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

---

## What it does

`setup.sh` runs a series of modules. It shows an **animated status board**
(spinner + live activity line + timer per module) and never hard-stops on a
single failure — it finishes and prints a `RESULT` bar plus a "needs attention"
list. Full detail log: `/var/log/kali-attackbox-setup.log`.

| Module | What it installs / configures |
|---|---|
| `base` | Full `apt` upgrade + build-essential, git, curl, jq, vim, tmux, powerline |
| `shell` | Handy aliases + `EDITOR`/`PATH` env, hooked into **zsh and bash** |
| `dev` | go, dotnet-sdk, poetry, pipx, pipenv, ansible-runner; PowerShell, Sublime, Chrome (best-effort) |
| `docker` | docker.io + docker-compose, enabled on boot, your user added to the `docker` group |
| `networking` | nmap, masscan, zmap, sshuttle, squid (:3128), sshd (root off), freetds, proxychains |
| `offensive` | Ensures the Kali arsenal (hashcat, ffuf, nuclei, responder, netexec, impacket, bloodhound, …), gowitness; clones impacket / PetitPotam / pre2k into `~/git`; enables Neo4j for BloodHound |
| `audit` | Full sudo I/O logging → `/var/log/sudo-io` |
| `desktop` | Disables sleep / screen-lock so the box won't nap mid-task (XFCE) |
| `remote` | xrdp on **tcp/3389**, XFCE session |
| `burp` | Burp Suite Community (always) + attempts Burp Pro silent install to `/opt/BurpSuitePro` |
| `veracrypt` | Installs VeraCrypt for encrypted artifact storage |
| `vm` | Auto-detects QEMU / VMware / VirtualBox and installs the matching guest agents |

---

## Prerequisites

- A **fresh Kali Linux install** (2024.x or newer) with the default **XFCE** desktop.
- **Internet access** for the first run (apt, Go, GitHub, third-party repos).
- A normal user with `sudo`. No hardcoded username — the script provisions whoever
  runs `sudo` (or the UID-1000 user). Run **as root via sudo**, not as root directly.

---

## Quick start

```bash
git clone https://github.com/alexsteward/kali-attackbox.git
cd kali-attackbox
chmod +x setup.sh
sudo ./setup.sh
sudo reboot
```

The slowest module is `base` (full system upgrade) — 10–30 min. It is not hung;
the live `↳` line shows package activity.

---

## Detailed setup

1. **Get it onto the box** — `git clone` (above) or copy the folder via USB. Copy the
   **whole folder** so `setup.sh` runs from its own directory.
2. **Run it:** `chmod +x setup.sh && sudo ./setup.sh`
3. **Watch** each module run with a spinner, a live "↳ current action" line, and a timer.
4. **Read the summary** — a `RESULT` bar and, if anything failed, a **⚠ needs attention**
   list plus **ℹ notes**. Details land in `/var/log/kali-attackbox-setup.log`.
5. **Reboot** — docker-group membership and VM guest agents apply on next login.

---

## Command-line flags

```bash
sudo ./setup.sh                    # full build
sudo ./setup.sh --only offensive   # run one module
sudo ./setup.sh --only dev,docker  # a comma-separated subset
sudo ./setup.sh --skip burp,remote # everything except these
sudo ./setup.sh --plain            # no animation (piping / dumb terminals)
```

Modules are idempotent — re-running is safe, so after a partial failure just re-run
the affected module, e.g. `sudo ./setup.sh --only veracrypt`.

---

## Modules

A few notes on the less-obvious ones:

- **`audit`** enables `sudo` input/output logging to `/var/log/sudo-io` — replay a
  session with `sudoreplay`. Useful for an engagement audit trail.
- **`offensive`** uses Kali's packaged Neo4j for **BloodHound** (which is a GUI app you
  launch from the menu, not a service). First visit to `http://localhost:7474` logs in
  with `neo4j/neo4j`; set a password, then point BloodHound at `bolt://localhost:7687`.
- **`veracrypt`** installs VeraCrypt (not in Kali's repos — pulled as the official `.deb`).
  Store sensitive artifacts in an encrypted container kept **off** the box.
- **`remote`** enables xrdp on tcp/3389 with an XFCE session.

---

## Troubleshooting

**A `dev` extra failed (dotnet / PowerShell / Sublime / Chrome).**
Those pull third-party repos; if one is down the module reports ✗ but the box is fine
(Chromium is the Chrome fallback). Re-run with `sudo ./setup.sh --only dev`.

**VeraCrypt failed.**
Bump `VER=` at the top of `mod_veracrypt` in `setup.sh` to the current release, or grab
the `.deb` from <https://veracrypt.io/en/Downloads.html>.

**`bad interpreter` / `^M` errors.**
The repo enforces LF via `.gitattributes`, so a clean clone is fine. If you edited on
Windows and hit this: `sed -i 's/\r$//' setup.sh`.

---

## Contributing

Issues and PRs welcome. Keep modules idempotent and self-contained, route command
output to `$LOG`, and use the `ok`/`warn`/`err`/`log` helpers so the status board and
summary stay accurate.

---

## License

MIT — see [LICENSE](LICENSE).
