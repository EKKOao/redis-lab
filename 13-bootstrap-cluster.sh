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

BOOTSTRAP_SCRIPT=/usr/local/sbin/redis-cluster-bootstrap.sh
RUNTIME_ENV=/etc/redis/cluster.env

cat >"$RUNTIME_ENV" <<EOF_RUNTIME
REDIS_CLUSTER_NODES="$REDIS_CLUSTER_NODES"
REDIS_CLUSTER_MIN_NODES="$REDIS_CLUSTER_MIN_NODES"
REDIS_CLUSTER_REPLICAS="$REDIS_CLUSTER_REPLICAS"
REDIS_CLUSTER_CREATOR_HOSTNAME="$REDIS_CLUSTER_CREATOR_HOSTNAME"
REDIS_PORT="$REDIS_PORT"
REDIS_REQUIRE_AUTH="$REDIS_REQUIRE_AUTH"
REDIS_LOCAL_SECRET_FILE="$REDIS_LOCAL_SECRET_FILE"
REDIS_ENABLE_TLS="$REDIS_ENABLE_TLS"
REDIS_TLS_REQUIRE_CLIENT_CERT="$REDIS_TLS_REQUIRE_CLIENT_CERT"
REDIS_TLS_LOCAL_CA_CERT="$REDIS_TLS_LOCAL_CA_CERT"
REDIS_TLS_LOCAL_CERT="$REDIS_TLS_LOCAL_CERT"
REDIS_TLS_LOCAL_KEY="$REDIS_TLS_LOCAL_KEY"
REDIS_TLS_ADMIN_CLIENT_CERT="$REDIS_TLS_ADMIN_CLIENT_CERT"
REDIS_TLS_ADMIN_CLIENT_KEY="$REDIS_TLS_ADMIN_CLIENT_KEY"
EOF_RUNTIME
chmod 0640 "$RUNTIME_ENV"
chown root:"$REDIS_GROUP" "$RUNTIME_ENV"

cat >"$BOOTSTRAP_SCRIPT" <<'EOF_BOOTSTRAP'
#!/usr/bin/env bash
set -euo pipefail

source /etc/redis/cluster.env
: "${REDIS_CLUSTER_NODES:=192.168.56.11 192.168.56.12 192.168.56.13 192.168.56.14 192.168.56.15 192.168.56.16}"
: "${REDIS_CLUSTER_MIN_NODES:=6}"
: "${REDIS_CLUSTER_REPLICAS:=1}"
: "${REDIS_CLUSTER_CREATOR_HOSTNAME:=redis1}"
: "${REDIS_PORT:=6379}"
: "${REDIS_REQUIRE_AUTH:=true}"
: "${REDIS_LOCAL_SECRET_FILE:=/etc/redis/redis.pass}"
: "${REDIS_ENABLE_TLS:=true}"
: "${REDIS_TLS_REQUIRE_CLIENT_CERT:=false}"
: "${REDIS_TLS_LOCAL_CA_CERT:=/etc/redis/tls/ca.crt}"
: "${REDIS_TLS_LOCAL_CERT:=/etc/redis/tls/redis.crt}"
: "${REDIS_TLS_LOCAL_KEY:=/etc/redis/tls/redis.key}"
: "${REDIS_TLS_ADMIN_CLIENT_CERT:=/vagrant/secrets/tls/client-admin.crt}"
: "${REDIS_TLS_ADMIN_CLIENT_KEY:=/vagrant/secrets/tls/client-admin.key}"

if [ "$(hostname -s)" != "$REDIS_CLUSTER_CREATOR_HOSTNAME" ]; then
  exit 0
fi

AUTH_ARGS=()
if [ "$REDIS_REQUIRE_AUTH" = "true" ]; then
  if [ ! -s "$REDIS_LOCAL_SECRET_FILE" ]; then
    echo "Missing Redis password file: $REDIS_LOCAL_SECRET_FILE" >&2
    exit 1
  fi
  PASS=$(tr -d '\r\n' < "$REDIS_LOCAL_SECRET_FILE")
  AUTH_ARGS=(--no-auth-warning -a "$PASS")
fi

TLS_ARGS=()
if [ "$REDIS_ENABLE_TLS" = "true" ]; then
  TLS_ARGS=(--tls --cacert "$REDIS_TLS_LOCAL_CA_CERT")
  if [ "$REDIS_TLS_REQUIRE_CLIENT_CERT" = "true" ]; then
    if [ -s "$REDIS_TLS_ADMIN_CLIENT_CERT" ] && [ -s "$REDIS_TLS_ADMIN_CLIENT_KEY" ]; then
    TLS_ARGS+=(--cert "$REDIS_TLS_ADMIN_CLIENT_CERT" --key "$REDIS_TLS_ADMIN_CLIENT_KEY")
  else
    TLS_ARGS+=(--cert "$REDIS_TLS_LOCAL_CERT" --key "$REDIS_TLS_LOCAL_KEY")
  fi
  fi
fi

read -r -a NODES <<< "$REDIS_CLUSTER_NODES"
if [ "${#NODES[@]}" -lt "$REDIS_CLUSTER_MIN_NODES" ]; then
  echo "Need at least $REDIS_CLUSTER_MIN_NODES nodes, got ${#NODES[@]}" >&2
  exit 1
fi

for ip in "${NODES[@]}"; do
  if ! timeout 3 redis-cli "${TLS_ARGS[@]}" "${AUTH_ARGS[@]}" -h "$ip" -p "$REDIS_PORT" PING | grep -q PONG; then
    echo "Redis not ready on $ip:$REDIS_PORT" >&2
    exit 1
  fi
  if redis-cli "${TLS_ARGS[@]}" "${AUTH_ARGS[@]}" -h "$ip" -p "$REDIS_PORT" CLUSTER INFO 2>/dev/null | grep -q '^cluster_state:ok'; then
    echo "Redis Cluster is already healthy."
    exit 0
  fi
done

CREATE_ARGS=()
for ip in "${NODES[@]}"; do
  CREATE_ARGS+=("$ip:$REDIS_PORT")
done

echo "Creating Redis Cluster with ${#NODES[@]} nodes and --cluster-replicas $REDIS_CLUSTER_REPLICAS"
yes yes | redis-cli "${TLS_ARGS[@]}" "${AUTH_ARGS[@]}" --cluster create "${CREATE_ARGS[@]}" --cluster-replicas "$REDIS_CLUSTER_REPLICAS"

sleep 5
redis-cli "${TLS_ARGS[@]}" "${AUTH_ARGS[@]}" -h "${NODES[0]}" -p "$REDIS_PORT" CLUSTER INFO | grep '^cluster_state:ok'
redis-cli "${TLS_ARGS[@]}" "${AUTH_ARGS[@]}" -h "${NODES[0]}" -p "$REDIS_PORT" CLUSTER NODES
EOF_BOOTSTRAP

chmod 0750 "$BOOTSTRAP_SCRIPT"
chown root:root "$BOOTSTRAP_SCRIPT"

cat >/etc/systemd/system/redis-cluster-bootstrap.service <<EOF_SERVICE
[Unit]
Description=Create Redis Cluster after all nodes are ready
After=redis.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$BOOTSTRAP_SCRIPT
EOF_SERVICE

cat >/etc/systemd/system/redis-cluster-bootstrap.timer <<'EOF_TIMER'
[Unit]
Description=Retry Redis Cluster bootstrap until successful

[Timer]
OnBootSec=45s
OnUnitActiveSec=30s
AccuracySec=5s
Persistent=true

[Install]
WantedBy=timers.target
EOF_TIMER

systemctl daemon-reload
if [ "$(hostname -s)" = "$REDIS_CLUSTER_CREATOR_HOSTNAME" ]; then
  systemctl enable --now redis-cluster-bootstrap.timer
else
  systemctl disable --now redis-cluster-bootstrap.timer >/dev/null 2>&1 || true
fi
