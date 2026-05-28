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

# Use a simple systemd service instead of Type=notify. This avoids depending on
# whether the Redis package was compiled with systemd notification support and
# is sufficient for a single Redis process managed by systemd.
cat >/etc/systemd/system/redis.service <<EOF_UNIT
[Unit]
Description=Redis 8 Cluster node
Documentation=https://redis.io/docs/latest/operate/oss_and_stack/management/scaling/
Wants=network-online.target disable-transparent-hugepages.service
After=network-online.target disable-transparent-hugepages.service

[Service]
Type=simple
User=$REDIS_USER
Group=$REDIS_GROUP
WorkingDirectory=$REDIS_DATA_DIR
RuntimeDirectory=redis
RuntimeDirectoryMode=0755
ExecStartPre=+/bin/mkdir -p $REDIS_RUN_DIR $REDIS_DATA_DIR $REDIS_LOG_DIR
ExecStartPre=+/bin/chown -R $REDIS_USER:$REDIS_GROUP $REDIS_RUN_DIR $REDIS_DATA_DIR $REDIS_LOG_DIR
ExecStart=/usr/bin/redis-server $REDIS_CONFIG_FILE --daemonize no --supervised no
ExecStop=/bin/kill -s TERM \$MAINPID
Restart=always
RestartSec=5
TimeoutStartSec=120
TimeoutStopSec=120
LimitNOFILE=100000
LimitNPROC=65535
UMask=0077

[Install]
WantedBy=multi-user.target
EOF_UNIT

systemctl daemon-reload
systemctl enable redis.service >/dev/null

if ! systemctl restart redis.service; then
  echo "redis.service failed to start. Recent journal:" >&2
  journalctl -u redis.service --no-pager -n 80 >&2 || true
  echo "Redis log tail:" >&2
  tail -n 80 "$REDIS_LOG_DIR/redis.log" >&2 || true
  exit 1
fi

sleep 2
systemctl is-active --quiet redis.service
systemctl status redis.service --no-pager | sed -n '1,18p'
