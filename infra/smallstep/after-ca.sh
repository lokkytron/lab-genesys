#!/bin/bash
set -euo pipefail

CONTAINER="smallstep"
STEP_HOME="/home/step"
SECRETS_DIR="$STEP_HOME/secrets"
CERTS_DIR="$STEP_HOME/certs"
PW="$SECRETS_DIR/password"
PP="$SECRETS_DIR/ansible_pp"
KEY="$SECRETS_DIR/ansible/ansible.jwk"
ROOT="$STEP_HOME/certs/root_ca.crt"

CA_HOST="${HOST_IP}"
CA_PORT="9000"
CA_DNS="smallstep.lab.loc"
CA_URL="https://${CA_DNS}:${CA_PORT}"

ADMIN_SUBJECT="admin@lab"
ADMIN_CERT="$STEP_HOME/admin.crt"
ADMIN_KEY="$STEP_HOME/admin.key"

# Host path for Ansible key exchange (bind-mounted into ansible:/key_exchange)
HOST_EXCHANGE_DIR="/home/${USER}/LAB/dockerdata/ansible_key_exchange"
K8S_FILES_DIR="/home/${USER}/LAB/infra/kubernetes/cert-manager"

# Generate random password for generate certificate
mkdir -p ${HOST_EXCHANGE_DIR}
head -c 32 /dev/urandom | base64 > ${HOST_EXCHANGE_DIR}/ansible_pp
chmod 600 ${HOST_EXCHANGE_DIR}/ansible_pp
docker cp "${HOST_EXCHANGE_DIR}/ansible_pp" "${CONTAINER}:${PP}"

# 1. Mint admin certificate if missing
if ! docker exec "$CONTAINER" test -f "$ADMIN_CERT" || ! docker exec "$CONTAINER" test -f "$ADMIN_KEY"; then
  echo "[Init] Minting admin certificate..."
  docker exec "$CONTAINER" step ca certificate "$ADMIN_SUBJECT" "$ADMIN_CERT" "$ADMIN_KEY" \
    --provisioner "admin" \
    --password-file "$PW" \
    --ca-url "$CA_URL" \
    --root "$ROOT"
else
  echo "[Info] Admin certificate already exists. Skipping."
fi

# 2. Ensure 'ansible' provisioner exists
PROVISIONER_EXISTS=$(docker exec "$CONTAINER" \
  sh -c "STEP_ADMIN_CERT='$ADMIN_CERT' STEP_ADMIN_KEY='$ADMIN_KEY' step ca provisioner list --ca-url '$CA_URL' --root '$ROOT' | grep -w 'ansible' || true")

if [ -z "$PROVISIONER_EXISTS" ]; then
  echo "[Init] Creating 'ansible' (SSH certs) provisioner..."
  docker exec -it "$CONTAINER" env STEP_ADMIN_CERT="$ADMIN_CERT" STEP_ADMIN_KEY="$ADMIN_KEY" \
    step ca provisioner add ansible \
      --type JWK \
      --create \
      --ssh \
      --password-file "$PP" \
      --ca-url "$CA_URL" \
      --root "$ROOT"

  echo "[Init] Creating 'ACME' (TLS certs) provisioner..."
  docker exec -it "$CONTAINER" env STEP_ADMIN_CERT="$ADMIN_CERT" STEP_ADMIN_KEY="$ADMIN_KEY" \
    step ca provisioner add acme \
      --type ACME \
      --create \
      --password-file "$PP" \
      --ca-url "$CA_URL" \
      --root "$ROOT"

else
  echo "[Info] 'ansible' provisioner already exists. Skipping."
fi

# 3. Export root CA cert to host exchange dir
echo "[Init] Exporting root CA cert to host exchange dir..."
mkdir -p "$HOST_EXCHANGE_DIR"
docker cp "${CONTAINER}:${ROOT}" "${HOST_EXCHANGE_DIR}/root_ca.crt"

# Envsubst for cert-manager clusterissuer config template
export CA_URL
export ROOT_CA_CONTENT="$(base64 -w0 ${HOST_EXCHANGE_DIR}/root_ca.crt)"
envsubst < $K8S_FILES_DIR/certmanager-clusterissuer.yaml.template > $K8S_FILES_DIR/certmanager-clusterissuer.yaml

# Create checksum file
sha256sum "${HOST_EXCHANGE_DIR}/root_ca.crt" | awk '{print $1}' > "${HOST_EXCHANGE_DIR}/root_ca.crt.sha256"

echo "[Init] Exporting SSH user-CA key + public key..."
docker cp "${CONTAINER}:${SECRETS_DIR}/ssh_user_ca_key" "${HOST_EXCHANGE_DIR}/ssh_user_ca_key"
docker cp "${CONTAINER}:${CERTS_DIR}/ssh_user_ca_key.pub" "${HOST_EXCHANGE_DIR}/ssh_user_ca_key.pub"

echo "[Init] Certificates and provisioner setup complete."

echo "[Init] Restarting smallstep container to load new provisioner…"
docker restart smallstep
