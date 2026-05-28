#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

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

apt-get update -y
apt-get install -y \
  acl lvm2 xfsprogs net-tools iproute2 jq curl ca-certificates gnupg lsb-release openssl \
  procps util-linux

if [ "${REDIS_INSTALL_SOURCE:-official_apt}" = "official_apt" ]; then
  install -d -m 0755 /usr/share/keyrings /etc/apt/sources.list.d /etc/apt/preferences.d
  curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg.tmp
  mv /usr/share/keyrings/redis-archive-keyring.gpg.tmp /usr/share/keyrings/redis-archive-keyring.gpg
  chmod 0644 /usr/share/keyrings/redis-archive-keyring.gpg

  CODENAME=$(lsb_release -cs)
  cat >/etc/apt/sources.list.d/redis.list <<EOF_REPO
# Redis official APT repository. Do not use Ubuntu's old redis-server package for this lab.
deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] ${REDIS_APT_REPO} ${CODENAME} main
EOF_REPO

  if [ "${REDIS_VERSION_PIN:-latest}" != "latest" ]; then
    cat >/etc/apt/preferences.d/redis <<EOF_PIN
Package: redis redis-server redis-tools redis-sentinel
Pin: version ${REDIS_VERSION_PIN}
Pin-Priority: 1001
EOF_PIN
  else
    rm -f /etc/apt/preferences.d/redis
  fi

  apt-get update -y
fi

apt-get install -y redis redis-server redis-tools

# Disable the distro/default unit. We install our own cluster-aware unit later.
systemctl disable --now redis-server.service >/dev/null 2>&1 || true
systemctl disable --now redis.service >/dev/null 2>&1 || true

REDIS_VERSION=$(redis-server --version | awk -F'[ =]' '{for (i=1;i<=NF;i++) if ($i=="v") {print $(i+1); exit}}')
if [ -z "$REDIS_VERSION" ]; then
  REDIS_VERSION=$(redis-server --version | sed -n 's/.*v=\([^ ]*\).*/\1/p')
fi

case "$REDIS_VERSION" in
  ${REDIS_EXPECTED_VERSION_PREFIX}*)
    ;;
  *)
    echo "Installed Redis version is $REDIS_VERSION, expected ${REDIS_EXPECTED_VERSION_PREFIX}.x." >&2
    echo "APT policy for redis-server:" >&2
    apt-cache policy redis-server >&2 || true
    exit 1
    ;;
esac

redis-server --version
redis-cli --version
