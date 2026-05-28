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

if ! command -v redis-server >/dev/null 2>&1; then
  echo "redis-server is not installed. Run 01-packages.sh first." >&2
  exit 1
fi

REDIS_VERSION=$(redis-server --version | sed -n 's/.*v=\([^ ]*\).*/\1/p')
case "$REDIS_VERSION" in
  ${REDIS_EXPECTED_VERSION_PREFIX}*) ;;
  *)
    echo "Installed Redis version is $REDIS_VERSION, expected ${REDIS_EXPECTED_VERSION_PREFIX}.x." >&2
    exit 1
    ;;
esac

systemctl disable --now redis-server.service >/dev/null 2>&1 || true
systemctl disable --now redis.service >/dev/null 2>&1 || true

mkdir -p "$REDIS_CONFIG_DIR" "$REDIS_DATA_DIR" "$REDIS_LOG_DIR" "$REDIS_BACKUP_DIR"
chown -R "$REDIS_USER:$REDIS_GROUP" "$REDIS_BASE_DIR" "$REDIS_CONFIG_DIR"
chmod 0750 "$REDIS_CONFIG_DIR" "$REDIS_DATA_DIR" "$REDIS_LOG_DIR" "$REDIS_BACKUP_DIR"

redis-server --version
