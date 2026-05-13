#!/bin/sh
echo "Starting Mehungry release..."

# ECS/Fargate may return multiple IPs.
# Use first one.
export POD_IP=$(hostname -i | awk '{print $1}')


# Try to find the binary automatically
RELEASE_BIN=$(find / -name "mehungry_umbrella" -type f -executable 2>/dev/null | head -1)

if [ -z "$RELEASE_BIN" ]; then
    echo "ERROR: Could not find mehungry_umbrella binary"
    exit 1
fi
echo "Found binary at: $RELEASE_BIN"

echo "Detected container IP: $POD_IP"

# Enable distributed Erlang
export RELEASE_DISTRIBUTION=name

# Create unique node name
export RELEASE_NODE="mehungry_umbrella@$POD_IP"

echo "Using RELEASE_NODE=$RELEASE_NODE"

# Verify cookie exists
if [ -z "$RELEASE_COOKIE" ]; then
  echo "ERROR: RELEASE_COOKIE is missing"
  exit 1
fi

echo "RELEASE_COOKIE detected"

# Start Elixir release
exec "$RELEASE_BIN" start

