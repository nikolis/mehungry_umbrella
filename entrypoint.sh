#!/bin/sh
set -e
echo "Starting Mehungry release..."

# ECS/Fargate may return multiple IPs — use the first one
export POD_IP=$(hostname -i | awk '{print $1}')
echo "Detected container IP: $POD_IP"

# Enable distributed Erlang with a unique node name per container
export RELEASE_DISTRIBUTION=name
export RELEASE_NODE="mehungry_umbrella@$POD_IP"
echo "Using RELEASE_NODE=$RELEASE_NODE"

if [ -z "$RELEASE_COOKIE" ]; then
  echo "ERROR: RELEASE_COOKIE is missing"
  exit 1
fi
echo "RELEASE_COOKIE detected"

# The release is always at this known path (set by Dockerfile WORKDIR /app)
exec /app/bin/mehungry_umbrella start
