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

if [ "${REDIS_ENABLE_TLS:-true}" != "true" ]; then
  echo "REDIS_ENABLE_TLS=false; skipping TLS certificate setup."
  exit 0
fi

umask 077
HOSTNAME_SHORT=$(hostname -s)
NODE_IP=${REDIS_NODE_IP:?REDIS_NODE_IP missing from $REDIS_ENV_FILE}
TLS_SHARED_NODE_PREFIX="$REDIS_TLS_SHARED_DIR/$HOSTNAME_SHORT"
ADMIN_PREFIX="$REDIS_TLS_SHARED_DIR/client-admin"

mkdir -p "$REDIS_TLS_SHARED_DIR" "$REDIS_TLS_DIR"
chmod 700 "$REDIS_TLS_SHARED_DIR" "$REDIS_TLS_DIR"

# In this lab, redis1 generates the CA. In production, use your enterprise PKI, Vault PKI, Smallstep, cert-manager, or cloud private CA.
if [ "$HOSTNAME_SHORT" = "$REDIS_CLUSTER_CREATOR_HOSTNAME" ]; then
  if [ ! -s "$REDIS_TLS_CA_KEY" ] || [ ! -s "$REDIS_TLS_CA_CERT" ]; then
    echo "Generating lab Redis TLS CA under $REDIS_TLS_SHARED_DIR"
    openssl genrsa -out "$REDIS_TLS_CA_KEY" 4096
    openssl req -x509 -new -nodes \
      -key "$REDIS_TLS_CA_KEY" \
      -sha256 \
      -days "$REDIS_TLS_CA_DAYS" \
      -out "$REDIS_TLS_CA_CERT" \
      -subj "/CN=redis-lab-ca"
    chmod 600 "$REDIS_TLS_CA_KEY"
    chmod 644 "$REDIS_TLS_CA_CERT"
  fi
fi

# Other nodes may provision after redis1, but this wait makes the script safe if parallel provisioning is enabled.
for _ in $(seq 1 120); do
  [ -s "$REDIS_TLS_CA_KEY" ] && [ -s "$REDIS_TLS_CA_CERT" ] && break
  echo "Waiting for lab CA files in $REDIS_TLS_SHARED_DIR ..."
  sleep 2
done

if [ ! -s "$REDIS_TLS_CA_KEY" ] || [ ! -s "$REDIS_TLS_CA_CERT" ]; then
  echo "Missing TLS CA key/cert. Expected $REDIS_TLS_CA_KEY and $REDIS_TLS_CA_CERT" >&2
  exit 1
fi

cat >"${TLS_SHARED_NODE_PREFIX}.openssl.cnf" <<EOF_CNF
[ req ]
default_bits       = 4096
prompt             = no
default_md         = sha256
distinguished_name = dn
req_extensions     = req_ext

[ dn ]
CN = ${HOSTNAME_SHORT}
O = redis-lab

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = ${HOSTNAME_SHORT}
DNS.2 = localhost
IP.1 = ${NODE_IP}
IP.2 = 127.0.0.1
EOF_CNF

if [ ! -s "${TLS_SHARED_NODE_PREFIX}.key" ] || [ ! -s "${TLS_SHARED_NODE_PREFIX}.crt" ]; then
  echo "Generating TLS certificate for $HOSTNAME_SHORT ($NODE_IP)"
  openssl genrsa -out "${TLS_SHARED_NODE_PREFIX}.key" 4096
  openssl req -new \
    -key "${TLS_SHARED_NODE_PREFIX}.key" \
    -out "${TLS_SHARED_NODE_PREFIX}.csr" \
    -config "${TLS_SHARED_NODE_PREFIX}.openssl.cnf"
  openssl x509 -req \
    -in "${TLS_SHARED_NODE_PREFIX}.csr" \
    -CA "$REDIS_TLS_CA_CERT" \
    -CAkey "$REDIS_TLS_CA_KEY" \
    -CAcreateserial \
    -out "${TLS_SHARED_NODE_PREFIX}.crt" \
    -days "$REDIS_TLS_CERT_DAYS" \
    -sha256 \
    -extensions req_ext \
    -extfile "${TLS_SHARED_NODE_PREFIX}.openssl.cnf"
  chmod 600 "${TLS_SHARED_NODE_PREFIX}.key"
  chmod 644 "${TLS_SHARED_NODE_PREFIX}.crt"
fi

# Optional admin/client certificate for mTLS testing and Redis Insight.
if [ "${REDIS_TLS_GENERATE_ADMIN_CLIENT_CERT:-true}" = "true" ] && [ "$HOSTNAME_SHORT" = "$REDIS_CLUSTER_CREATOR_HOSTNAME" ]; then
  if [ ! -s "${ADMIN_PREFIX}.key" ] || [ ! -s "${ADMIN_PREFIX}.crt" ]; then
    cat >"${ADMIN_PREFIX}.openssl.cnf" <<'EOF_CLIENT_CNF'
[ req ]
default_bits       = 4096
prompt             = no
default_md         = sha256
distinguished_name = dn
req_extensions     = req_ext

[ dn ]
CN = redis-admin-client
O = redis-lab

[ req_ext ]
extendedKeyUsage = clientAuth
keyUsage = digitalSignature, keyEncipherment
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = redis-admin-client
EOF_CLIENT_CNF
    openssl genrsa -out "${ADMIN_PREFIX}.key" 4096
    openssl req -new -key "${ADMIN_PREFIX}.key" -out "${ADMIN_PREFIX}.csr" -config "${ADMIN_PREFIX}.openssl.cnf"
    openssl x509 -req \
      -in "${ADMIN_PREFIX}.csr" \
      -CA "$REDIS_TLS_CA_CERT" \
      -CAkey "$REDIS_TLS_CA_KEY" \
      -CAcreateserial \
      -out "${ADMIN_PREFIX}.crt" \
      -days "$REDIS_TLS_CERT_DAYS" \
      -sha256 \
      -extensions req_ext \
      -extfile "${ADMIN_PREFIX}.openssl.cnf"
    chmod 600 "${ADMIN_PREFIX}.key"
    chmod 644 "${ADMIN_PREFIX}.crt"
  fi
fi

install -m 0640 -o "$REDIS_USER" -g "$REDIS_GROUP" "$REDIS_TLS_CA_CERT" "$REDIS_TLS_LOCAL_CA_CERT"
install -m 0640 -o "$REDIS_USER" -g "$REDIS_GROUP" "${TLS_SHARED_NODE_PREFIX}.crt" "$REDIS_TLS_LOCAL_CERT"
install -m 0600 -o "$REDIS_USER" -g "$REDIS_GROUP" "${TLS_SHARED_NODE_PREFIX}.key" "$REDIS_TLS_LOCAL_KEY"
chown -R "$REDIS_USER:$REDIS_GROUP" "$REDIS_TLS_DIR"
chmod 750 "$REDIS_TLS_DIR"

openssl x509 -in "$REDIS_TLS_LOCAL_CERT" -noout -subject -issuer -dates
