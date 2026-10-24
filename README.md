# settings_auto_update

## Automatic updates

`auto-update.sh` detects the distribution using `/etc/os-release` and runs
package updates on Debian and Ubuntu. Other distributions are reported as
unsupported and are not modified.

Install and schedule the updater with one command (requires `curl` and `sudo`):

```sh
sudo bash -o pipefail -c 'curl -fsSL https://raw.githubusercontent.com/TeraStale/settings_auto_update/main/install.sh | bash'
```

The installer downloads the updater, installs `cron` if needed, and enables a
daily check at 04:00 UTC. Package upgrades run only when at least 3 days have
passed since the previous successful upgrade. A pending reboot is still checked
daily and is performed only during the 04:00-06:00 UTC window.

The script runs as root and automatically installs missing utility packages
with APT (for example `logger` and `flock`) when needed. If an update reports
that a reboot is required, the daily check retries the reboot at the next
scheduled run.
