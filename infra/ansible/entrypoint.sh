#!/bin/sh
set -eu

echo "[Ansible] Waiting for Smallstep CA TCP/HTTP at: ${CA_URL}/health"
until curl -skf "${CA_URL}/health" >/dev/null 2>&1; do
  sleep 3
done

echo "[Ansible] Generating SSH keypair..."
mkdir -p "${EXCHANGE_DIR}"
if [ ! -f "${EXCHANGE_DIR}/ansible_id_rsa" ]; then
  ssh-keygen -t rsa -b 4096 -f "${EXCHANGE_DIR}/ansible_id_rsa" -N "" -C ansible@lab
else
  echo "[Ansible] SSH keypair already exists. Skipping."
fi

echo "[Ansible] Waiting for root certificate in exchange..."
until [ -f "${ROOT_EX}" ] && [ -f "${ROOT_SHA}" ]; do
  sleep 2
done

echo "[Ansible] Verifying root certificate checksum..."
calc_sha="$(sha256sum "${ROOT_EX}" | awk '{print $1}')"
expect_sha="$(cat "${ROOT_SHA}")"
if [ "${calc_sha}" != "${expect_sha}" ]; then
  echo "[Ansible] ERROR: Root CA checksum mismatch!"
  exit 1
fi
echo "[Ansible] Checksum OK."

echo "[Ansible] Installing root certificate to ${ROOT_DST}..."
mkdir -p "${STEP_ROOT_DIR}"
cp "${ROOT_EX}" "${ROOT_DST}"
chmod 0644 "${ROOT_DST}"

echo "[Ansible] Bootstrapping Smallstep CLI trust..."
if [ ! -f "${STEP_DEFAULTS}" ]; then
  FP="$(step certificate fingerprint "${ROOT_DST}")"
  step ca bootstrap --ca-url "${CA_URL}" --fingerprint "${FP}"
else
  echo "[Ansible] step CLI already bootstrapped. Skipping."
fi

echo "[Ansible] Requesting SSH certificate for principal 'ansible'..."
if [ ! -f "${EXCHANGE_DIR}/ansible_id_rsa-cert.pub" ]; then
  step ssh certificate ansible \
    "${EXCHANGE_DIR}/ansible_id_rsa.pub" \
    --issuer ansible \
    --sign \
    --ca-url "${CA_URL}" \
    --root "${ROOT_DST}" \
    --not-after 15m \
    --no-agent \
    --provisioner-password-file "${EXCHANGE_DIR}/ansible_pp"
else
  echo "[Ansible] SSH certificate already exists. Skipping."
fi

echo "[Ansible] Writing Ansible inventory..."
mkdir -p /inventories/lab
cat > /inventories/lab/hosts.ini <<EOF
[local]
127.0.0.1 ansible_connection=local

[hostsrv]
${HOST_IP} ansible_user=ansible \
ansible_ssh_private_key_file=${EXCHANGE_DIR}/ansible_id_rsa \
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o CertificateFile=${EXCHANGE_DIR}/ansible_id_rsa-cert.pub'

[k8snodes]
${K8S_MASTER_HOST} ansible_host=${K8S_MASTER_IP}
${K8S_WORKER1_HOST} ansible_host=${K8S_WORKER1_IP}
${K8S_WORKER2_HOST} ansible_host=${K8S_WORKER2_IP}

[k8snodes:vars]
ansible_user=ansible
ansible_ssh_private_key_file=${EXCHANGE_DIR}/ansible_id_rsa
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes -o PreferredAuthentications=publickey'

EOF

mkdir -p /etc/ansible
cat > /etc/ansible/ansible.cfg <<EOF
[defaults]
inventory = /inventories/lab/hosts.ini
force_color = True
EOF

echo "[Ansible] Ready."
exec sleep infinity
