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

SUDO_FILE=/etc/sudoers.d/redis
cat >"$SUDO_FILE" <<EOF_SUDO
$REDIS_USER ALL=(root) NOPASSWD: /usr/bin/systemctl start redis.service
$REDIS_USER ALL=(root) NOPASSWD: /usr/bin/systemctl stop redis.service
$REDIS_USER ALL=(root) NOPASSWD: /usr/bin/systemctl restart redis.service
$REDIS_USER ALL=(root) NOPASSWD: /usr/bin/systemctl status redis.service
$REDIS_USER ALL=(root) NOPASSWD: /usr/bin/journalctl -u redis.service
EOF_SUDO
chmod 0440 "$SUDO_FILE"
visudo -cf "$SUDO_FILE"
