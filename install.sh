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

if ! command -v systemctl >/dev/null 2>&1; then
    printf '%s\n' "ERROR: systemd is required to enable the scheduled job." >&2
    exit 1
fi

script_url=https://raw.githubusercontent.com/TeraStale/settings_auto_update/main/auto-update.sh
temporary_script=$(mktemp)
trap 'rm -f "$temporary_script"' EXIT
curl --fail --location --silent --show-error "$script_url" --output "$temporary_script"
install -D -m 0755 "$temporary_script" /usr/local/sbin/server-auto-update.sh

if ! command -v cron >/dev/null 2>&1; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y cron
fi

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