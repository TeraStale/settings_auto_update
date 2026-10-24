#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
    printf '%s\n' "ERROR: run this installer as root (for example, with sudo)." >&2
    exit 1
fi

if [[ ! -r /etc/os-release ]]; then
    printf '%s\n' "ERROR: cannot identify this operating system (/etc/os-release is missing)." >&2
    exit 1
fi

# shellcheck disable=SC1091
. /etc/os-release

case "${ID:-}" in
    debian|ubuntu)
        ;;
    *)
        printf "ERROR: unsupported distribution '%s'. Only Debian and Ubuntu are supported.\n" "${ID:-unknown}" >&2
        exit 1
        ;;
esac

missing_packages=()
if ! command -v systemctl >/dev/null 2>&1; then
    missing_packages+=(systemd)
fi

if ! command -v curl >/dev/null 2>&1; then
    missing_packages+=(curl)
fi

if ! command -v logger >/dev/null 2>&1 || ! command -v flock >/dev/null 2>&1; then
    missing_packages+=(util-linux)
fi

if ! command -v cron >/dev/null 2>&1; then
    missing_packages+=(cron)
fi

if (( ${#missing_packages[@]} > 0 )); then
    if ! command -v apt-get >/dev/null 2>&1; then
        printf '%s\n' "ERROR: apt-get is required to install missing packages." >&2
        exit 1
    fi
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing_packages[@]}"
fi

script_url=https://raw.githubusercontent.com/TeraStale/settings_auto_update/main/auto-update.sh
temporary_script=$(mktemp)
trap 'rm -f "$temporary_script"' EXIT
curl --fail --location --silent --show-error "$script_url" --output "$temporary_script"
install -D -m 0755 "$temporary_script" /usr/local/sbin/server-auto-update.sh

install -d -m 0755 /etc/cron.d
cat > /etc/cron.d/server-auto-update <<'EOF'
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
CRON_TZ=UTC
0 4 * * * root /usr/local/sbin/server-auto-update.sh
EOF
chmod 0644 /etc/cron.d/server-auto-update
systemctl enable --now cron.service

printf '%s\n' "Installed. The job checks daily at 04:00 UTC and upgrades packages no more than once every 3 days."