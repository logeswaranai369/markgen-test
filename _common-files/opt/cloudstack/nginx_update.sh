#!/bin/bash
set -euo pipefail

APP="nginx"
INSTALLED_VERSION="None"
UPSTREAM_SOURCE="apt:nginx"

echo "== ${APP} update check =="
echo "Installed version: ${INSTALLED_VERSION}"

if [ -z "${UPSTREAM_SOURCE}" ]; then
  echo "No upstream source configured for ${APP}; cannot check for updates."
  exit 0
fi

echo "Upstream source: ${UPSTREAM_SOURCE}"
# TODO(markgen): implement per-source version check (github releases / apt / npm / pypi ...)
# For now this is a check-only stub that reports the configured source. Applying an update
# is intentionally NOT automatic (may require config/DB migration) — see SPEC §2.6 / §9.
echo "Update check not yet implemented. Please check ${UPSTREAM_SOURCE} manually."
