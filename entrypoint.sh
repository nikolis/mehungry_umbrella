#!/bin/sh
set -e
echo "Starting Mehungry release..."

# Node naming / Erlang distribution is decided per platform in rel/env.sh.eex
# (sourced by the release script), not here.

# Clustered nodes must share a cookie.
if [ -z "$RELEASE_COOKIE" ]; then
  echo "ERROR: RELEASE_COOKIE is missing"
  exit 1
fi
echo "RELEASE_COOKIE detected"

# The release is always at this known path (set by Dockerfile WORKDIR /app)
exec /app/bin/mehungry_umbrella start
