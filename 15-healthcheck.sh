#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [ -f "$SCRIPT_DIR/00-env.sh" ]; then
  # shellcheck source=00-env.sh
  source "$SCRIPT_DIR/00-env.sh"
elif [ -f /vagrant/00-env.sh ]; then
  # shellcheck source=/vagrant/00-env.sh
  source /vagrant/00-env.sh
else
  echo "Unable to locate 00-env.sh. Run from the project directory or through Vagrant." >&2
  exit 1
fi

AUTH_ARGS=()
if [ "$REDIS_REQUIRE_AUTH" = "true" ] && [ -s "$REDIS_LOCAL_SECRET_FILE" ]; then
  PASS=$(tr -d '\r\n' < "$REDIS_LOCAL_SECRET_FILE")
  AUTH_ARGS=(--no-auth-warning -a "$PASS")
fi

TLS_ARGS=()
if [ "${REDIS_ENABLE_TLS:-true}" = "true" ]; then
  TLS_ARGS=(--tls --cacert "$REDIS_TLS_LOCAL_CA_CERT")
  if [ "${REDIS_TLS_REQUIRE_CLIENT_CERT:-false}" = "true" ]; then
    if [ -s "${REDIS_TLS_ADMIN_CLIENT_CERT:-}" ] && [ -s "${REDIS_TLS_ADMIN_CLIENT_KEY:-}" ]; then
      TLS_ARGS+=(--cert "$REDIS_TLS_ADMIN_CLIENT_CERT" --key "$REDIS_TLS_ADMIN_CLIENT_KEY")
    else
      TLS_ARGS+=(--cert "$REDIS_TLS_LOCAL_CERT" --key "$REDIS_TLS_LOCAL_KEY")
    fi
  fi
fi

FIRST_NODE=$(echo "$REDIS_CLUSTER_NODES" | awk '{print $1}')
echo "Checking Redis Cluster through $FIRST_NODE:$REDIS_PORT"
redis-cli "${TLS_ARGS[@]}" "${AUTH_ARGS[@]}" -h "$FIRST_NODE" -p "$REDIS_PORT" PING
redis-cli "${TLS_ARGS[@]}" "${AUTH_ARGS[@]}" -h "$FIRST_NODE" -p "$REDIS_PORT" CLUSTER INFO
redis-cli "${TLS_ARGS[@]}" "${AUTH_ARGS[@]}" -h "$FIRST_NODE" -p "$REDIS_PORT" CLUSTER NODES
redis-cli "${TLS_ARGS[@]}" "${AUTH_ARGS[@]}" --cluster check "$FIRST_NODE:$REDIS_PORT"
