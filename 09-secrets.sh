#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [ -f "$SCRIPT_DIR/00-env.sh" ]; then
  # shellcheck source=00-env.sh
  source "$SCRIPT_DIR/00-env.sh"
elif [ -f /vagrant/00-env.sh ]; then
  # Vagrant's shell path provisioner copies scripts to /tmp; this fallback keeps manual/path execution safe.
  # shellcheck source=/vagrant/00-env.sh
  source /vagrant/00-env.sh
else
  echo "Unable to locate 00-env.sh. Run from the project directory or through Vagrant." >&2
  exit 1
fi

mkdir -p "$REDIS_CONFIG_DIR"

if [ "$REDIS_REQUIRE_AUTH" != "true" ]; then
  rm -f "$REDIS_LOCAL_SECRET_FILE"
  echo "Redis AUTH disabled by REDIS_REQUIRE_AUTH=false. Do not use this on an exposed network."
  exit 0
fi

if [ -n "${REDIS_PASSWORD:-}" ]; then
  printf '%s\n' "$REDIS_PASSWORD" > "$REDIS_LOCAL_SECRET_FILE"
elif [ -n "$REDIS_SHARED_SECRET_FILE" ] && [ -d "$(dirname "$REDIS_SHARED_SECRET_FILE")" ]; then
  if [ "$(hostname -s)" = "$REDIS_CLUSTER_CREATOR_HOSTNAME" ] && [ ! -s "$REDIS_SHARED_SECRET_FILE" ]; then
    umask 077
    openssl rand -base64 48 | tr -d '=+/[:space:]' | cut -c1-48 > "$REDIS_SHARED_SECRET_FILE"
  fi
  for _ in $(seq 1 120); do
    [ -s "$REDIS_SHARED_SECRET_FILE" ] && break
    sleep 2
  done
  if [ ! -s "$REDIS_SHARED_SECRET_FILE" ]; then
    echo "Shared Redis secret was not found at $REDIS_SHARED_SECRET_FILE" >&2
    exit 1
  fi
  cp "$REDIS_SHARED_SECRET_FILE" "$REDIS_LOCAL_SECRET_FILE"
else
  echo "REDIS_REQUIRE_AUTH=true but no secret source is available." >&2
  echo "Set REDIS_PASSWORD or create REDIS_SHARED_SECRET_FILE on every node." >&2
  exit 1
fi

chown "$REDIS_USER:$REDIS_GROUP" "$REDIS_LOCAL_SECRET_FILE"
chmod 0400 "$REDIS_LOCAL_SECRET_FILE"
echo "Redis AUTH secret installed at $REDIS_LOCAL_SECRET_FILE"
