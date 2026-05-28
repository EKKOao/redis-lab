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

NODE_IP=${REDIS_NODE_IP:-}
if [ -z "$NODE_IP" ]; then
  NODE_IP=$(ip -o -4 addr show scope global | awk -v prefix="$REDIS_PRIVATE_CIDR_PREFIX" '{split($4,a,"/"); if (index(a[1], prefix)==1) {print a[1]; exit}}')
fi

if [ -z "$NODE_IP" ]; then
  NODE_IP=$(ip -o -4 route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')
fi

if [ -z "$NODE_IP" ]; then
  echo "Could not determine Redis node IP. Set REDIS_NODE_IP explicitly." >&2
  exit 1
fi

cat >"$REDIS_ENV_FILE" <<EOF_NODE
REDIS_NODE_IP=$NODE_IP
REDIS_PORT=$REDIS_PORT
REDIS_BUS_PORT=$REDIS_BUS_PORT
EOF_NODE
chmod 0640 "$REDIS_ENV_FILE"
chown "$REDIS_USER:$REDIS_GROUP" "$REDIS_ENV_FILE"

# Open firewall only if UFW is active. Cloud/security-group rules are still required in real production.
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q '^Status: active'; then
  ufw allow from "$NFS_BACKUP_NETWORK" to any port "$REDIS_PORT" proto tcp || true
  ufw allow from "$NFS_BACKUP_NETWORK" to any port "$REDIS_BUS_PORT" proto tcp || true
fi

echo "Redis announce IP: $NODE_IP"
