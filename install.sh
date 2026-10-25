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

remove_update_cron_entries() {
    local pattern='(^|[[:space:]/])(apt-get|apt|aptitude|unattended-upgrade|apt\.systemd\.daily)([[:space:]]|$)'
    local cron_file temporary_file root_crontab

    for cron_file in /etc/crontab /etc/cron.d/*; do
        [[ -f "$cron_file" && ! -L "$cron_file" ]] || continue
        if grep -Eiq "$pattern" "$cron_file"; then
            temporary_file=$(mktemp "${cron_file}.XXXXXX")
            awk -v pattern="$pattern" 'tolower($0) !~ pattern' "$cron_file" > "$temporary_file"
            chmod --reference="$cron_file" "$temporary_file"
            chown --reference="$cron_file" "$temporary_file"
            mv "$temporary_file" "$cron_file"
            printf 'Removed package-update cron entries from %s.\n' "$cron_file"
        fi
    done

    if command -v crontab >/dev/null 2>&1; then
        root_crontab=$(mktemp)
        if crontab -l > "$root_crontab" 2>/dev/null && grep -Eiq "$pattern" "$root_crontab"; then
            awk -v pattern="$pattern" 'tolower($0) !~ pattern' "$root_crontab" | crontab -
            printf '%s\n' "Removed package-update entries from root's crontab."
        fi
        rm -f "$root_crontab"
    fi
}

remove_update_cron_entries

install -d -m 0755 /etc/cron.d
cat > /etc/cron.d/server-auto-update <<'EOF'
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
CRON_TZ=UTC
0 4 * * * root /usr/local/sbin/server-auto-update.sh
0 5 * * * root /usr/local/sbin/server-auto-update.sh
EOF
chmod 0644 /etc/cron.d/server-auto-update
systemctl enable --now cron.service

printf '%s\n' "Installed. Packages are checked daily at 04:00 UTC; a required reboot is retried at 05:00 UTC."