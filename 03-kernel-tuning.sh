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

cat >/etc/security/limits.d/redis.conf <<EOF_LIMITS
$REDIS_USER soft nofile 100000
$REDIS_USER hard nofile 100000
$REDIS_USER soft nproc  65535
$REDIS_USER hard nproc  65535
EOF_LIMITS

cat >/etc/sysctl.d/99-redis.conf <<'EOF_SYSCTL'
# Redis background saves and AOF rewrites need overcommit enabled to avoid fork failures.
vm.overcommit_memory = 1

# Redis warns when the TCP backlog is lower than tcp-backlog in redis.conf.
net.core.somaxconn = 65535

# Conservative network tuning for many client connections.
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_keepalive_time = 300
EOF_SYSCTL

sysctl -p /etc/sysctl.d/99-redis.conf >/dev/null

# Persistent THP disablement.
cat >/etc/systemd/system/disable-transparent-hugepages.service <<'EOF_THP'
[Unit]
Description=Disable Transparent Huge Pages for Redis
DefaultDependencies=no
After=sysinit.target local-fs.target
Before=redis.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'for f in /sys/kernel/mm/transparent_hugepage/enabled /sys/kernel/mm/transparent_hugepage/defrag; do [ -w "$f" ] && echo never > "$f" || true; done'

[Install]
WantedBy=basic.target
EOF_THP

systemctl daemon-reload
systemctl enable --now disable-transparent-hugepages.service >/dev/null 2>&1 || true
