# settings_auto_update

## Automatic updates

`auto-update.sh` detects the distribution using `/etc/os-release` and runs
package updates on Debian and Ubuntu. Other distributions are reported as
unsupported and are not modified.

Install and schedule the updater with one command (requires `sudo` and an APT-based Debian/Ubuntu server):

```sh
sudo bash -o pipefail -c 'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y curl && curl -fsSL https://raw.githubusercontent.com/TeraStale/settings_auto_update/main/install.sh | bash'
```

The installer installs any missing dependencies (`curl`, `cron`, `util-linux`,
or `systemd`), removes existing APT package-update entries from system cron
files and root's crontab, then schedules the updater daily at 04:00 and 05:00
UTC. Package upgrades run at most once per UTC day. The second run checks for a
pending reboot and performs it within the 04:00-06:00 UTC window.

The script runs as root and automatically installs missing utility packages
with APT (for example `logger` and `flock`) when needed. If an update reports
that a reboot is required, the 05:00 UTC run retries the reboot on the same day.
