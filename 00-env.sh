#!/usr/bin/env bash
# Shared Redis Cluster defaults. Override with environment variables or edit this file.

# Required production topology: minimum 6 nodes = 3 masters + 3 replicas.
REDIS_CLUSTER_NODES=${REDIS_CLUSTER_NODES:-"192.168.56.11 192.168.56.12 192.168.56.13 192.168.56.14 192.168.56.15 192.168.56.16"}
REDIS_CLUSTER_MIN_NODES=${REDIS_CLUSTER_MIN_NODES:-6}
REDIS_CLUSTER_MASTERS=${REDIS_CLUSTER_MASTERS:-3}
REDIS_CLUSTER_REPLICAS=${REDIS_CLUSTER_REPLICAS:-1}
REDIS_CLUSTER_CREATOR_HOSTNAME=${REDIS_CLUSTER_CREATOR_HOSTNAME:-redis1}
REDIS_PRIVATE_CIDR_PREFIX=${REDIS_PRIVATE_CIDR_PREFIX:-192.168.56.}

# Redis package source and version.
# Ubuntu 22.04's default repository ships Redis 6.0.x; production-style installs use Redis' official APT repo.
REDIS_INSTALL_SOURCE=${REDIS_INSTALL_SOURCE:-official_apt}
REDIS_APT_REPO=${REDIS_APT_REPO:-https://packages.redis.io/deb}
# Redis official packages currently use epoch 6 in apt versions, for example 6:8.6.x-1rl1~jammy1.
# Set REDIS_VERSION_PIN=latest to avoid pinning, or override to a more specific apt version.
REDIS_VERSION_PIN=${REDIS_VERSION_PIN:-6:8.6.*}
REDIS_EXPECTED_MAJOR=${REDIS_EXPECTED_MAJOR:-8}
REDIS_EXPECTED_VERSION_PREFIX=${REDIS_EXPECTED_VERSION_PREFIX:-8.6}

# Runtime.
# With TLS enabled, REDIS_PORT is the TLS client port. Plaintext TCP is disabled with port 0.
REDIS_PORT=${REDIS_PORT:-6379}
REDIS_BUS_PORT=${REDIS_BUS_PORT:-$((REDIS_PORT + 10000))}
REDIS_USER=${REDIS_USER:-redis}
REDIS_GROUP=${REDIS_GROUP:-redis}
REDIS_UID=${REDIS_UID:-1122}
REDIS_GID=${REDIS_GID:-1122}

# Paths.
REDIS_BASE_DIR=${REDIS_BASE_DIR:-/mnt/redis}
REDIS_DATA_DIR=${REDIS_DATA_DIR:-$REDIS_BASE_DIR/data}
REDIS_LOG_DIR=${REDIS_LOG_DIR:-$REDIS_BASE_DIR/logs}
REDIS_BACKUP_DIR=${REDIS_BACKUP_DIR:-$REDIS_BASE_DIR/backup}
REDIS_RUN_DIR=${REDIS_RUN_DIR:-/run/redis}
REDIS_CONFIG_DIR=${REDIS_CONFIG_DIR:-/etc/redis}
REDIS_CONFIG_FILE=${REDIS_CONFIG_FILE:-$REDIS_CONFIG_DIR/redis.conf}
REDIS_ENV_FILE=${REDIS_ENV_FILE:-$REDIS_CONFIG_DIR/node.env}

# Persistence and memory policy.
# For cache-only workloads you may set REDIS_SAVE_RULES="" and REDIS_APPENDONLY=no.
REDIS_SAVE_RULES=${REDIS_SAVE_RULES:-"save 900 1|save 300 10|save 60 10000"}
REDIS_APPENDONLY=${REDIS_APPENDONLY:-yes}
REDIS_APPENDFSYNC=${REDIS_APPENDFSYNC:-everysec}
REDIS_MAXMEMORY=${REDIS_MAXMEMORY:-0}
REDIS_MAXMEMORY_POLICY=${REDIS_MAXMEMORY_POLICY:-noeviction}

# Security.
# Redis Cluster should not be internet exposed. Use firewalls/security groups.
# Set REDIS_REQUIRE_AUTH=false only in isolated labs.
REDIS_REQUIRE_AUTH=${REDIS_REQUIRE_AUTH:-true}
REDIS_SHARED_SECRET_FILE=${REDIS_SHARED_SECRET_FILE:-/vagrant/secrets/redis_cluster_password}
REDIS_LOCAL_SECRET_FILE=${REDIS_LOCAL_SECRET_FILE:-$REDIS_CONFIG_DIR/redis.pass}
REDIS_DISABLE_DANGEROUS_COMMANDS=${REDIS_DISABLE_DANGEROUS_COMMANDS:-false}

# TLS.
# v6 defaults to TLS-only Redis traffic: plaintext Redis TCP is disabled by 11-config.sh.
# Lab CA/key material is placed under /vagrant/secrets/tls for convenience. Replace with PKI/Vault in production.
REDIS_ENABLE_TLS=${REDIS_ENABLE_TLS:-true}
REDIS_TLS_SHARED_DIR=${REDIS_TLS_SHARED_DIR:-/vagrant/secrets/tls}
REDIS_TLS_DIR=${REDIS_TLS_DIR:-$REDIS_CONFIG_DIR/tls}
REDIS_TLS_CA_KEY=${REDIS_TLS_CA_KEY:-$REDIS_TLS_SHARED_DIR/ca.key}
REDIS_TLS_CA_CERT=${REDIS_TLS_CA_CERT:-$REDIS_TLS_SHARED_DIR/ca.crt}
REDIS_TLS_LOCAL_CA_CERT=${REDIS_TLS_LOCAL_CA_CERT:-$REDIS_TLS_DIR/ca.crt}
REDIS_TLS_LOCAL_CERT=${REDIS_TLS_LOCAL_CERT:-$REDIS_TLS_DIR/redis.crt}
REDIS_TLS_LOCAL_KEY=${REDIS_TLS_LOCAL_KEY:-$REDIS_TLS_DIR/redis.key}
REDIS_TLS_CERT_DAYS=${REDIS_TLS_CERT_DAYS:-825}
REDIS_TLS_CA_DAYS=${REDIS_TLS_CA_DAYS:-3650}
# false/no means clients authenticate with Redis AUTH/ACL only. Set true to require client certificates too.
REDIS_TLS_REQUIRE_CLIENT_CERT=${REDIS_TLS_REQUIRE_CLIENT_CERT:-false}
# Generate a reusable admin client certificate in /vagrant/secrets/tls/client-admin.* for Redis Insight/redis-cli mTLS testing.
REDIS_TLS_GENERATE_ADMIN_CLIENT_CERT=${REDIS_TLS_GENERATE_ADMIN_CLIENT_CERT:-true}
REDIS_TLS_ADMIN_CLIENT_CERT=${REDIS_TLS_ADMIN_CLIENT_CERT:-$REDIS_TLS_SHARED_DIR/client-admin.crt}
REDIS_TLS_ADMIN_CLIENT_KEY=${REDIS_TLS_ADMIN_CLIENT_KEY:-$REDIS_TLS_SHARED_DIR/client-admin.key}
REDIS_TLS_MIN_VERSION=${REDIS_TLS_MIN_VERSION:-TLSv1.2}

# Optional NFS backup share. This is not used for Redis Cluster runtime data.
ENABLE_NFS_BACKUP=${ENABLE_NFS_BACKUP:-false}
NFS_BACKUP_SERVER_IP=${NFS_BACKUP_SERVER_IP:-192.168.56.11}
NFS_BACKUP_NETWORK=${NFS_BACKUP_NETWORK:-192.168.56.0/24}

# Optional LVM. In Vagrant this package attaches a 20GB disk per node.
# In real production, point REDIS_LVM_DISK to the correct dedicated data disk.
# If no suitable disk is found, scripts safely fall back to directories on the root filesystem.
REDIS_USE_LVM=${REDIS_USE_LVM:-true}
REDIS_VG=${REDIS_VG:-vg_redis}
REDIS_MIN_LVM_DISK_BYTES=${REDIS_MIN_LVM_DISK_BYTES:-10737418240}
REDIS_DATA_LV_SIZE=${REDIS_DATA_LV_SIZE:-8G}
REDIS_LOG_LV_SIZE=${REDIS_LOG_LV_SIZE:-2G}
REDIS_BACKUP_LV_SIZE=${REDIS_BACKUP_LV_SIZE:-4G}

# Administration helpers.
REDIS_ADMIN_BIN_DIR=${REDIS_ADMIN_BIN_DIR:-/usr/local/bin}
