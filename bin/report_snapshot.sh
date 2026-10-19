#!/usr/bin/env bash
#
# Trigger the app-status snapshot (docs/app_status.md §7 / `mix report.snapshot`).
#
# Secrets (prod read-only DB URL, GA4 service-account key path, GSC site,
# Pinterest creds) live in a LOCAL, gitignored env file so they never appear in
# the command line or the repo:
#
#   $REPORT_SNAPSHOT_ENV  or  ~/.config/mehungry/report.env
#
# Copy bin/report_snapshot.env.example to that path and fill it in once.
#
# Usage:
#   bin/report_snapshot.sh            # full report, 28-day window
#   bin/report_snapshot.sh --days 7
#   bin/report_snapshot.sh --row      # just the §6 log row
#
set -euo pipefail

# Run from the umbrella root regardless of where we're invoked from.
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ENV_FILE="${REPORT_SNAPSHOT_ENV:-$HOME/.config/mehungry/report.env}"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
else
  echo "report_snapshot: env file not found at $ENV_FILE" >&2
  echo "Create it from bin/report_snapshot.env.example and fill in the values." >&2
  exit 1
fi

exec mix report.snapshot "$@"
