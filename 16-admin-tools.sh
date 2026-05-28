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

install -d -m 0755 "$REDIS_ADMIN_BIN_DIR"

cat >"$REDIS_ADMIN_BIN_DIR/redis-cluster-cli" <<EOF_CLI
#!/usr/bin/env bash
set -euo pipefail
PASS=""
if [ -s "$REDIS_LOCAL_SECRET_FILE" ]; then
  PASS=\$(tr -d '\\r\\n' < "$REDIS_LOCAL_SECRET_FILE")
fi
AUTH_ARGS=()
if [ -n "\$PASS" ]; then
  AUTH_ARGS=(--no-auth-warning -a "\$PASS")
fi
TLS_ARGS=()
if [ "${REDIS_ENABLE_TLS}" = "true" ]; then
  TLS_ARGS=(--tls --cacert "$REDIS_TLS_LOCAL_CA_CERT")
  if [ "${REDIS_TLS_REQUIRE_CLIENT_CERT}" = "true" ]; then
    if [ -s "$REDIS_TLS_ADMIN_CLIENT_CERT" ] && [ -s "$REDIS_TLS_ADMIN_CLIENT_KEY" ]; then
    TLS_ARGS+=(--cert "$REDIS_TLS_ADMIN_CLIENT_CERT" --key "$REDIS_TLS_ADMIN_CLIENT_KEY")
  else
    TLS_ARGS+=(--cert "$REDIS_TLS_LOCAL_CERT" --key "$REDIS_TLS_LOCAL_KEY")
  fi
  fi
fi
exec redis-cli "\${TLS_ARGS[@]}" "\${AUTH_ARGS[@]}" -c -h "\${REDIS_HOST:-127.0.0.1}" -p "\${REDIS_PORT:-$REDIS_PORT}" "\$@"
EOF_CLI
chmod 0755 "$REDIS_ADMIN_BIN_DIR/redis-cluster-cli"

cat >"$REDIS_ADMIN_BIN_DIR/redis-cluster-check" <<EOF_CHECK
#!/usr/bin/env bash
set -euo pipefail
PASS=""
if [ -s "$REDIS_LOCAL_SECRET_FILE" ]; then
  PASS=\$(tr -d '\\r\\n' < "$REDIS_LOCAL_SECRET_FILE")
fi
AUTH_ARGS=()
if [ -n "\$PASS" ]; then
  AUTH_ARGS=(--no-auth-warning -a "\$PASS")
fi
TLS_ARGS=()
if [ "${REDIS_ENABLE_TLS}" = "true" ]; then
  TLS_ARGS=(--tls --cacert "$REDIS_TLS_LOCAL_CA_CERT")
  if [ "${REDIS_TLS_REQUIRE_CLIENT_CERT}" = "true" ]; then
    if [ -s "$REDIS_TLS_ADMIN_CLIENT_CERT" ] && [ -s "$REDIS_TLS_ADMIN_CLIENT_KEY" ]; then
    TLS_ARGS+=(--cert "$REDIS_TLS_ADMIN_CLIENT_CERT" --key "$REDIS_TLS_ADMIN_CLIENT_KEY")
  else
    TLS_ARGS+=(--cert "$REDIS_TLS_LOCAL_CERT" --key "$REDIS_TLS_LOCAL_KEY")
  fi
  fi
fi
NODE="\${1:-$(echo "$REDIS_CLUSTER_NODES" | awk '{print $1}'):$REDIS_PORT}"
exec redis-cli "\${TLS_ARGS[@]}" "\${AUTH_ARGS[@]}" --cluster check "\$NODE"
EOF_CHECK
chmod 0755 "$REDIS_ADMIN_BIN_DIR/redis-cluster-check"

cat >"$REDIS_ADMIN_BIN_DIR/redis-cluster-info" <<EOF_INFO
#!/usr/bin/env bash
set -euo pipefail
redis-cluster-cli CLUSTER INFO
echo
redis-cluster-cli CLUSTER NODES
EOF_INFO
chmod 0755 "$REDIS_ADMIN_BIN_DIR/redis-cluster-info"

cat >"$REDIS_ADMIN_BIN_DIR/redis-tls-probe" <<EOF_TLS
#!/usr/bin/env bash
set -euo pipefail
HOST="\${1:-127.0.0.1}"
PORT="\${2:-$REDIS_PORT}"
if [ "${REDIS_ENABLE_TLS}" != "true" ]; then
  echo "REDIS_ENABLE_TLS=false; openssl probe skipped." >&2
  exit 1
fi
exec openssl s_client -connect "\${HOST}:\${PORT}" -CAfile "$REDIS_TLS_LOCAL_CA_CERT" -servername "\${HOST}" </dev/null
EOF_TLS
chmod 0755 "$REDIS_ADMIN_BIN_DIR/redis-tls-probe"

cat <<EOF_DONE
Installed Redis administration helpers:
  redis-cluster-cli [command...]
  redis-cluster-info
  redis-cluster-check [host:port]
  redis-tls-probe [host] [port]
EOF_DONE
