#!/usr/bin/env bash
set -Eeuo pipefail

ensure_dependencies() {
    local missing=()

    if ! command -v logger >/dev/null 2>&1; then
        missing+=(util-linux)
    fi

    if ! command -v flock >/dev/null 2>&1; then
        missing+=(util-linux)
    fi

    if ! command -v systemctl >/dev/null 2>&1 && ! command -v shutdown >/dev/null 2>&1; then
        missing+=(systemd)
    fi

    if (( ${#missing[@]} > 0 )); then
        log "Installing required packages: ${missing[*]}"
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update
            DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
        else
            log "ERROR: apt-get is not available, cannot install missing dependencies."
            exit 1
        fi
    fi
}

log() {
    printf '%s\n' "$*"
    if command -v logger >/dev/null 2>&1; then
        logger -t server-auto-update -- "$*"
    fi
}

if [[ ${EUID} -ne 0 ]]; then
    log "ERROR: run this script as root."
    exit 1
fi

if [[ ! -r /etc/os-release ]]; then
    log "ERROR: cannot identify this operating system (/etc/os-release is missing)."
    exit 1
fi

ensure_dependencies

# /etc/os-release is the standard shell-compatible distribution identifier file.
# shellcheck disable=SC1091
. /etc/os-release

case "${ID:-}" in
    debian|ubuntu)
        ;;
    *)
        log "ERROR: unsupported distribution '${ID:-unknown}'. Only Debian and Ubuntu are supported."
        exit 1
        ;;
esac

exec 9>/run/lock/server-auto-update.lock
if ! flock -n 9; then
    log "Another update run is already in progress; exiting."
    exit 0
fi

state_file=/var/lib/server-auto-update/last-update
day_start=$(date -u -d 'today 00:00' +%s)
if [[ -r "$state_file" ]]; then
    last_update=$(<"$state_file")
else
    last_update=0
fi

if [[ "$last_update" =~ ^[0-9]+$ ]] && (( last_update >= day_start )); then
    log "Packages were already updated today; checking whether a reboot is required."
else
    log "Starting package update on ${PRETTY_NAME:-$ID}."
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get -y \
        -o Dpkg::Options::=--force-confold \
        upgrade
    install -d -m 0755 /var/lib/server-auto-update
    printf '%s\n' "$(date +%s)" > "$state_file"
fi

if [[ ! -e /var/run/reboot-required && ! -e /run/reboot-required ]]; then
    log "Update complete; reboot is not required."
    exit 0
fi

utc_hour=$(date -u +%H)
if [[ "$utc_hour" == "04" || "$utc_hour" == "05" ]]; then
    log "A reboot is required; rebooting within the allowed 04:00-06:00 UTC window."
    if command -v systemctl >/dev/null 2>&1; then
        systemctl reboot
    elif command -v shutdown >/dev/null 2>&1; then
        shutdown -r now
    else
        log "ERROR: no supported reboot command available."
    fi
else
    log "A reboot is required, but the current time is outside 04:00-06:00 UTC. It will be retried at the next scheduled run."
fi
