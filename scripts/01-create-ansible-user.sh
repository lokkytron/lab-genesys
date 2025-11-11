#!/bin/bash
set -euo pipefail
IFS=$'\n\t'
umask 022

# This script is intended to be executed on the HOST with sudo privileges.
# - Creates the 'ansible' user if it does not exist.
# - Ensures ~/.ssh and authorized_keys contain the CA as 'cert-authority ...' without removing existing keys.
# - Configures /etc/sudoers.d/ansible and validates with visudo.
# - Ensures /etc/sudoers includes '#includedir /etc/sudoers.d'.

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CA_PUB_KEY="${PROJECT_DIR}/dockerdata/ansible_key_exchange/ssh_user_ca_key.pub"

# Paths and constants
SUDOERS_DIR="/etc/sudoers.d"
SUDOERS_FILE="${SUDOERS_DIR}/ansible"
SUDOERS_BLOCK=$(cat <<EOF
$SUDOERS_CONTENT
EOF
)

INCLUDEDIR_LINE="@includedir /etc/sudoers.d"

log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
err()  { echo "[ERROR] $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || err "Required command not found: $1"
}

require_cmd sudo
require_cmd visudo
require_cmd useradd
require_cmd id
require_cmd grep
require_cmd install
require_cmd mktemp

# 1) Create entities (ansible user and ansible-ops group) if missing
if ! id ansible &>/dev/null; then
  log "Creating user 'ansible'..."
  sudo useradd -m -U -s /bin/bash ansible
else
  log "User 'ansible' already exists."
fi

ANSIBLE_HOME="$(getent passwd ansible | awk -F: '{print $6}')"
[ -n "${ANSIBLE_HOME}" ] || err "Unable to resolve HOME directory for 'ansible'"

if ! getent group ansible-ops &>/dev/null; then
  log "Creating group 'ansible-ops'..."
  sudo groupadd ansible-ops
else
  log "Group 'ansible-ops' already exists."
fi

# 2) Configure sshd to trust our CA for user certificates
CA_DEST="/etc/ssh/ca_user.pub"

if [ -f "${CA_PUB_KEY}" ]; then
  log "Installing CA public key to ${CA_DEST}..."
  sudo install -o root -g root -m 0644 "${CA_PUB_KEY}" "${CA_DEST}"
else
  err "CA public key not found at ${CA_PUB_KEY}"
fi

# Ensure sshd_config has TrustedUserCAKeys line
if ! sudo grep -Eq "^[#]*\s*TrustedUserCAKeys\s+${CA_DEST}" /etc/ssh/sshd_config; then
  log "Adding TrustedUserCAKeys to sshd_config..."
  echo "TrustedUserCAKeys ${CA_DEST}" | sudo tee -a /etc/ssh/sshd_config >/dev/null
else
  log "TrustedUserCAKeys already configured in sshd_config."
fi

# Reload sshd to apply changes
log "Reloading sshd..."
if command -v systemctl >/dev/null; then
  sudo systemctl reload sshd
else
  sudo service ssh reload
fi

# 3) Configure /etc/sudoers.d/ansible with validation
sudo mkdir -p "${SUDOERS_DIR}"

write_sudoers_safely() {
  local content="$1" target="$2"
  local tmp; tmp="$(mktemp)"
  echo "${content}" > "${tmp}"
  # Validate syntax with visudo
  if ! sudo visudo -cf "${tmp}" >/dev/null; then
    rm -f "${tmp}"
    err "Sudoers validation failed. No changes applied."
  fi
  # If target exists and is identical, skip update
  if [ -f "${target}" ] && sudo diff -q "${tmp}" "${target}" >/dev/null 2>&1; then
    rm -f "${tmp}"
    log "Sudoers already contains the expected configuration for 'ansible'."
    return 0
  fi
  # Install atomically with correct permissions
  log "Updating ${target}..."
  sudo install -o root -g root -m 0440 "${tmp}" "${target}"
  rm -f "${tmp}"
}

write_sudoers_safely "${SUDOERS_BLOCK}" "${SUDOERS_FILE}"

# 4) Ensure /etc/sudoers includes the sudoers.d include
if ! sudo grep -Fxq "${INCLUDEDIR_LINE}" /etc/sudoers; then
  log "Adding '${INCLUDEDIR_LINE}' to /etc/sudoers..."
  tmp_all="$(mktemp)"
  sudo cp /etc/sudoers "${tmp_all}"
  echo "${INCLUDEDIR_LINE}" | sudo tee -a "${tmp_all}" > /dev/null
  if sudo visudo -cf "${tmp_all}" >/dev/null; then
    sudo cp "${tmp_all}" /etc/sudoers
    sudo chmod 0440 /etc/sudoers
  else
    err "Validation of /etc/sudoers after adding includedir failed. No changes applied."
  fi
  rm -f "${tmp_all}"
else
  log "Include for /etc/sudoers.d already present in /etc/sudoers."
fi

log "[OK] User 'ansible' prepared: sudoers, .ssh, and cert-authority configured."
