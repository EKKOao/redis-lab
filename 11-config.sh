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
source "$REDIS_ENV_FILE"

mkdir -p "$REDIS_CONFIG_DIR" "$REDIS_DATA_DIR" "$REDIS_LOG_DIR" "$REDIS_RUN_DIR"

PASSWORD=""
if [ "$REDIS_REQUIRE_AUTH" = "true" ]; then
  if [ ! -s "$REDIS_LOCAL_SECRET_FILE" ]; then
    echo "Missing Redis password file: $REDIS_LOCAL_SECRET_FILE" >&2
    exit 1
  fi
  PASSWORD=$(tr -d '\r\n' < "$REDIS_LOCAL_SECRET_FILE")
fi

if [ "${REDIS_ENABLE_TLS:-true}" = "true" ]; then
  for f in "$REDIS_TLS_LOCAL_CA_CERT" "$REDIS_TLS_LOCAL_CERT" "$REDIS_TLS_LOCAL_KEY"; do
    if [ ! -s "$f" ]; then
      echo "TLS is enabled but missing required TLS file: $f" >&2
      exit 1
    fi
  done
  REDIS_PORT_BLOCK=$(cat <<EOF_PORT
# TLS-only Redis listener. Plaintext TCP is disabled.
port 0
tls-port $REDIS_PORT
tls-cert-file $REDIS_TLS_LOCAL_CERT
tls-key-file $REDIS_TLS_LOCAL_KEY
tls-ca-cert-file $REDIS_TLS_LOCAL_CA_CERT
tls-auth-clients $([ "$REDIS_TLS_REQUIRE_CLIENT_CERT" = "true" ] && echo yes || echo no)
tls-replication yes
tls-cluster yes
tls-protocols "$REDIS_TLS_MIN_VERSION TLSv1.3"
EOF_PORT
)
else
  REDIS_PORT_BLOCK=$(cat <<EOF_PORT
# Plaintext Redis listener. Use only on isolated/private networks.
port $REDIS_PORT
EOF_PORT
)
fi

cat >"$REDIS_CONFIG_FILE" <<EOF_CONF
# Managed by provisioning scripts. Edit 00-env.sh and rerun 11-config.sh for deterministic changes.

bind 127.0.0.1 $REDIS_NODE_IP
protected-mode yes
$REDIS_PORT_BLOCK
tcp-backlog 65535
timeout 0
tcp-keepalive 300

supervised no
daemonize no
pidfile $REDIS_RUN_DIR/redis.pid
loglevel notice
logfile $REDIS_LOG_DIR/redis.log
always-show-logo no

# Persistence
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes
dbfilename dump.rdb
dir $REDIS_DATA_DIR
appendonly $REDIS_APPENDONLY
appendfilename "appendonly.aof"
appendfsync $REDIS_APPENDFSYNC
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb

# Redis Cluster
cluster-enabled yes
cluster-config-file nodes.conf
cluster-node-timeout 5000
cluster-require-full-coverage yes
cluster-migration-barrier 1
cluster-announce-ip $REDIS_NODE_IP
cluster-announce-port $REDIS_PORT
cluster-announce-bus-port $REDIS_BUS_PORT
cluster-port $REDIS_BUS_PORT

# Memory policy. REDIS_MAXMEMORY=0 means Redis can use available memory; set an explicit cap in production.
maxmemory $REDIS_MAXMEMORY
maxmemory-policy $REDIS_MAXMEMORY_POLICY

# Slowlog and latency observability
slowlog-log-slower-than 10000
slowlog-max-len 256
latency-monitor-threshold 100
EOF_CONF

# Save rules are pipe-delimited to make overrides easy in one env var.
if [ -n "$REDIS_SAVE_RULES" ]; then
  echo "$REDIS_SAVE_RULES" | tr '|' '\n' >> "$REDIS_CONFIG_FILE"
else
  echo "save \"\"" >> "$REDIS_CONFIG_FILE"
fi

if [ "$REDIS_REQUIRE_AUTH" = "true" ]; then
  cat >>"$REDIS_CONFIG_FILE" <<EOF_AUTH

# Authentication. All cluster nodes must share this same password.
# requirepass configures the default user password; masterauth lets replicas authenticate.
requirepass $PASSWORD
masterauth $PASSWORD
EOF_AUTH
fi

if [ "$REDIS_DISABLE_DANGEROUS_COMMANDS" = "true" ]; then
  cat >>"$REDIS_CONFIG_FILE" <<'EOF_RENAME'

# Optional hardening. Enable only after confirming your operational tooling does not need these commands.
rename-command FLUSHALL ""
rename-command FLUSHDB ""
rename-command CONFIG ""
rename-command DEBUG ""
EOF_RENAME
fi

chown "$REDIS_USER:$REDIS_GROUP" "$REDIS_CONFIG_FILE"
chmod 0640 "$REDIS_CONFIG_FILE"

# These are non-fatal sanity checks. Service startup will print detailed logs on failure.
redis-server "$REDIS_CONFIG_FILE" --test-memory 2 >/dev/null || true
redis-server "$REDIS_CONFIG_FILE" --check-system >/dev/null 2>&1 || true
