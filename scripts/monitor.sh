#!/usr/bin/env bash

set -u -o pipefail

usage() {
  echo "Usage: $0 SERVICE" >&2
  echo "Example: $0 docker" >&2
}

if [[ $# -ne 1 || -z "$1" ]]; then
  usage
  exit 2
fi

service="$1"
service_rc=0

if ! command -v systemctl >/dev/null 2>&1; then
  echo "systemctl is unavailable on this host; run the script on a systemd VM."
  exit 2
fi

if systemctl is-active --quiet "$service"; then
  echo "Service '$service': active"
else
  service_rc=1
  status="$(systemctl is-active "$service" 2>/dev/null || true)"
  echo "Service '$service': ${status:-inactive}"
  echo "Last 10 journal lines:"
  if ! journalctl -u "$service" -n 10 --no-pager 2>&1; then
    echo "Unable to read journal for '$service'."
  fi
fi

syslog="${SYSLOG_PATH:-/var/log/syslog}"
if [[ ! -r "$syslog" ]]; then
  echo "Error count in $syslog during the last hour: unavailable (file is absent or unreadable)."
  exit "$service_rc"
fi

if ! command -v date >/dev/null 2>&1; then
  echo "Error count in $syslog during the last hour: unavailable (date is missing)."
  exit "$service_rc"
fi

now_epoch="$(date +%s)"
current_year="$(date +%Y)"
error_count="$({
  grep -iE 'error|failed|critical|alert|emerg' "$syslog" || true
} | awk -v now="$now_epoch" -v year="$current_year" '
  function month_number(name) {
    split("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec", months, " ")
    for (i = 1; i <= 12; i++) if (months[i] == name) return i
    return 0
  }
  {
    # Ubuntu uses the standard "Mon DD HH:MM:SS" syslog prefix.
    month = month_number($1)
    if (month == 0) next
    timestamp = sprintf("%04d-%02d-%02d %s", year, month, $2, $3)
    command = "date -d \"" timestamp "\" +%s 2>/dev/null"
    command | getline epoch
    close(command)
    if (epoch != "" && epoch >= now - 3600 && epoch <= now) count++
  }
  END { print count + 0 }
')"

echo "Error count in $syslog during the last hour: $error_count"
exit "$service_rc"
