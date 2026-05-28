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

if ! getent group "$REDIS_GROUP" >/dev/null; then
  groupadd -g "$REDIS_GID" -r "$REDIS_GROUP"
fi

if ! id -u "$REDIS_USER" >/dev/null 2>&1; then
  useradd -u "$REDIS_UID" -g "$REDIS_GROUP" -r -s /usr/sbin/nologin -d "$REDIS_BASE_DIR" "$REDIS_USER"
else
  usermod -g "$REDIS_GROUP" -d "$REDIS_BASE_DIR" -s /usr/sbin/nologin "$REDIS_USER" || true
fi
