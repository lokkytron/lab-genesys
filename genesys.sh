#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
umask 022

## === CORE LAB VARIABLES ================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GROUP_VARS="infra/ansible/inventories/lab/group_vars"
HOST_IP=$(ip route get 1 | awk '{print $7; exit}')
LAB_PATH=$(pwd)
LAB_DOMAIN="lab.loc"
LAB_NET_BASE="192.168.5"
PLAYBOOK_DEBUG="" ## Change to -vv, -vvv, or more to get more verbosity on playbook execution

## === DOCKER NETWORK VARIABLES ==========================================
DOCKER_NETWORK_NAME="labdockernet"
DOCKER_BRIDGE_NAME="br_${DOCKER_NETWORK_NAME}"
DOCKER_SUBNET="172.25.0.0/16"
DOCKER_GATEWAY="172.25.0.1"

## === LIBVIRT VARIABLES =================================================
LIBVIRT_NETWORK_NAME="k8s-net"
LIBVIRT_IMAGE_DIR="/var/lib/libvirt/images"

## === KUBERNETES NODES VARIABLES ========================================
K8S_MASTER_IP="${LAB_NET_BASE}.11"
K8S_WORKER1_IP="${LAB_NET_BASE}.21"
K8S_WORKER2_IP="${LAB_NET_BASE}.22"

K8S_PREFIX="k8s"
K8S_MASTER_HOST="${K8S_PREFIX}-master"
K8S_WORKER1_HOST="${K8S_PREFIX}-worker1"
K8S_WORKER2_HOST="${K8S_PREFIX}-worker2"

METALLB_RANGE="${LAB_NET_BASE}.2-${LAB_NET_BASE}.9"
DOCKER_SERVICES_NS="docker-services"
TELEMETRY_NS="telemetry"

echo "DEBUG: script started" >&2

# ANSIBLE user (LOW RIGHTS admin)
SUDOERS_CONTENT=$(cat <<'EOF'
  Cmnd_Alias ANSIBLE_TEST_CMD = /bin/true
  Cmnd_Alias ANSIBLE_USER_CMDS = \
      /usr/sbin/groupadd -f ansible-ops, \
      /usr/sbin/adduser --disabled-password --gecos "" --ingroup ansible-ops eph-usr-[A-Za-z0-9]*, \
      /usr/sbin/usermod -aG ansible-ops eph-usr-[A-Za-z0-9]*, \
      /usr/sbin/userdel -r eph-usr-[A-Za-z0-9]*, \
      /usr/bin/install -d -m 700 -o * -g * /home/eph-usr-[A-Za-z0-9]*/.ssh, \
      /bin/chmod 0750 /home/eph-usr-[A-Za-z0-9]*
  Cmnd_Alias ANSIBLE_CA_USER_CMD = \
      /bin/grep -qxF TrustedUserCAKeys\ /etc/ssh/ca_user.pub\ /etc/ssh/sshd_config, \
      /bin/systemctl reload sshd.service, /bin/systemctl reload ssh.service, \
      /usr/bin/cp /tmp/sshd_config.tmp /etc/ssh/sshd_config, \
      /usr/bin/rm /tmp/sshd_config.tmp
  ansible ALL=(ALL) NOPASSWD: ANSIBLE_TEST_CMD, ANSIBLE_USER_CMDS, ANSIBLE_CA_USER_CMD
  %ansible-ops ALL=(ALL) NOPASSWD:ALL
EOF
)

## === LOGGING ===========================================================
# Colors for pretty output
GREEN="\e[32m"
BLUE="\e[34m"
CYAN="\e[36m"
YELLOW="\e[33m"
RED="\e[31m"
RESET="\e[0m"

# Icons (safe Unicode escapes)
WARN_ICON="\u26A0"        # ⚠
JET_ICON="\U0001F680"     # 🚀
LOCK_ICON="\U0001F512"    # 🔒
OK_ICON="\u2714"          # ✔
ERR_ICON="\u274C"         # ❌
WAIT_ICON="\u23F3"        # ⏳

log()   { echo -e "${GREEN} $*${RESET}"; }
warn()  { echo -e "${YELLOW} $*${RESET}"; }
info()  { echo -e "${BLUE} $*${RESET}"; }
error() { echo -e "${RED} $*${RESET}" >&2; exit 1; }
title() {
    local text="$*"
    local len=${#text}
    local border
    border=$(printf '%*s' "$len" '' | tr ' ' '=')

    echo -e "${CYAN}===${border}===${RESET}"
    echo -e "${CYAN}    ${text}${RESET}"
    echo -e "${CYAN}===${border}===${RESET}"
}

## === RESET MANAGER =====================================================
RESET_OPTION="${1:-}"

if [[ "$RESET_OPTION" =~ ^--reset- ]]; then
    title "${WARN_ICON} RESET REQUEST DETECTED"
    warn "You have requested to remove the following:"

    case "$RESET_OPTION" in
        --reset-lab)
            echo " - Stop and remove Docker containers: ansible, smallstep"
            echo " - Delete folders: dockerdata/smallstep, dockerdata/ansible_key_exchange"
            echo " - Destroy and undefine all K8S VMs"
            ;;
        --reset-docker)
            echo " - Stop and remove Docker containers: ansible, smallstep"
            echo " - Delete folders: dockerdata/smallstep, dockerdata/ansible_key_exchange"
            ;;
        --reset-cluster)
            echo " - Run Ansible jobs: kubeadm reset + clean K8S config files"
            ;;
        --reset-nodes)
            echo " - Destroy and undefine all K8S VMs"
            ;;
        *)
            error "Unknown reset option: $RESET_OPTION"
            exit 1
            ;;
    esac

    read -rp "Are you sure you want to proceed? (yes/no): " CONFIRM
    if [[ "$CONFIRM" != "yes" ]]; then
        error "Aborted by user!"
        exit 0
    fi

    warn "Executing $RESET_OPTION..."

    case "$RESET_OPTION" in
        --reset-lab)
            docker compose down
            if ! docker network ls --format '{{.Name}}' | grep -q "^${DOCKER_NETWORK_NAME}$"; then
                docker network remove $(docker network list |grep ${DOCKER_NETWORK_NAME}| awk '{print $1}')
            fi
            rm -rf dockerdata/smallstep/* dockerdata/ansible_key_exchange/*
            for vm in $(sudo virsh list --all | awk 'NR>2 {print $2}' | grep "${K8S_PREFIX}"); do
                sudo virsh destroy "$vm";
            done
            for vm in $(sudo virsh list --all | awk 'NR>2 {print $2}' | grep "${K8S_PREFIX}"); do
                sudo virsh undefine "$vm";
                sudo rm -rf $LIBVIRT_IMAGE_DIR/$vm-sys.img
                sudo rm -rf $LIBVIRT_IMAGE_DIR/$vm-cidata.img
            done
            ;;
        --reset-docker)
            docker compose down
            if ! docker network ls --format '{{.Name}}' | grep -q "^${DOCKER_NETWORK_NAME}$"; then
                docker network remove $(docker network list |grep ${DOCKER_NETWORK_NAME}| awk '{print $1}')
            fi
            rm -rf dockerdata/smallstep/* dockerdata/ansible_key_exchange/*
            ;;
        --reset-cluster)
            ansible-playbook playbooks/reset-k8s-cluster.yml
            ;;
        --reset-nodes)
            for vm in $(sudo virsh list --all | awk 'NR>2 {print $2}' | grep "${K8S_PREFIX}"); do
                sudo virsh destroy "$vm";
            done
            for vm in $(sudo virsh list --all | awk 'NR>2 {print $2}' | grep "${K8S_PREFIX}"); do
                sudo virsh undefine "$vm";
                sudo rm -rf $LIBVIRT_IMAGE_DIR/$vm-sys.img
                sudo rm -rf $LIBVIRT_IMAGE_DIR/$vm-cidata.img
            done
            ;;
    esac

    log "${OK_ICON} $RESET_OPTION completed."
    exit 0
fi

title "${JET_ICON} Starting Lab Environment Setup"

## === 1. FIRST ENVSUBST VARS ============================================
warn "[1/11] ENV vars export and replacement..."

export HOST_IP LAB_PATH LAB_NET_BASE LAB_DOMAIN SUDOERS_CONTENT
export DOCKER_NETWORK_NAME DOCKER_BRIDGE_NAME \
       DOCKER_SUBNET DOCKER_GATEWAY
export LIBVIRT_NETWORK_NAME LIBVIRT_IMAGE_DIR
export K8S_MASTER_IP K8S_WORKER1_IP K8S_WORKER2_IP \
       K8S_MASTER_HOST K8S_WORKER1_HOST K8S_WORKER2_HOST
export METALLB_RANGE TELEMETRY_NS DOCKER_SERVICES_NS

# --- .env for docker compose ---
envsubst < .env.template > .env

# --- all.yml for ansible group_vars ---
envsubst < "$SCRIPT_DIR/$GROUP_VARS/all.yml.template" > "$SCRIPT_DIR/$GROUP_VARS/all.yml"

# --- Generate configs from templates using envsubst ---
TEMPLATES=(
  "infra/proxy/nginx.conf"
  "infra/coredns/Corefile"
  "infra/kubernetes/k8s-net.xml"
  "infra/coredns/zones/LAB_DOMAIN.db"
  "infra/kubernetes/metallb/metallb-config.yaml"
  "infra/kubernetes/grafana/grafana-ingress.yaml"
  "infra/kubernetes/promtail/promtail-configmap.yaml"
  "infra/kubernetes/prometheus/prometheus-ingress.yaml"
  "infra/kubernetes/docker-services/docker-services.yaml"
  "infra/kubernetes/alert-manager/alertmanager-deployment.yaml"
)

for file in "${TEMPLATES[@]}"; do
    if [[ "$file" == "infra/proxy/nginx.conf" ]]; then
        # Only substitute LAB_NET_BASE to avoid breaking Nginx's own $vars
        envsubst '$LAB_NET_BASE' < "${file}.template" > "$file"
    elif [[ "$file" == "infra/coredns/zones/LAB_DOMAIN.db" ]]; then
        # Only substitute HOST_IP and LAB_DOMAIN to avoid breaking CoreDNS's own $vars
        envsubst '$LAB_DOMAIN $HOST_IP' < "${file}.template" > "$file"
        # Renaming Create CoreDNS db file to match CoreDNS requirements
        mv "$file" "infra/coredns/zones/${LAB_DOMAIN}.db"
    else
        # Substitute all exported vars
        envsubst < "${file}.template" > "$file"
    fi
done

log "${OK_ICON} Main ENV vars set:"
log "   - HOST_IP set to ${HOST_IP}"
log "   - LAB_PATH set to ${LAB_PATH}"
log "   - LAB_NET_BASE set to ${LAB_NET_BASE}"
log "${OK_ICON} DOCKER network (${DOCKER_NETWORK_NAME}) vars set:"
log "   - Network bridge set to ${DOCKER_BRIDGE_NAME}"
log "   - Subnet range is ${DOCKER_SUBNET}"
log "${OK_ICON} K8s node IPs/hostnames set:"
log "   - ${K8S_MASTER_IP}/${K8S_MASTER_HOST}"
log "   - ${K8S_WORKER1_IP}/${K8S_WORKER1_HOST}"
log "   - ${K8S_WORKER2_IP}/${K8S_WORKER2_HOST}"
log "${OK_ICON} Rest of template files generated: "
log "   - libvirt xml network file"
log "   - proxy .conf file "
log "   - metallb configmap file "

## === 2. Check if all docker requisites are installed ===================
warn "[2/11] Checking and installing pre-requisites..."
bash $SCRIPT_DIR/scripts/00-docker-pre-check.sh
sleep 1

## === 3. Starting Certificate Authority =================================
warn "[3/11] Starting Core DNS and Smallstep CA..."
docker compose up -d coredns smallstep

# Waiting for smallstep container to be running
warn "${WAIT_ICON} Waiting for smallstep container to be running..."
MAX_WAIT=30
SECONDS_WAITED=0
while [ "$(docker inspect -f '{{.State.Running}}' smallstep 2>/dev/null)" != "true" ]; do
    sleep 1
    SECONDS_WAITED=$((SECONDS_WAITED+1))
    if [ $SECONDS_WAITED -ge $MAX_WAIT ]; then
        error "${ERR_ICON} Timeout: smallstep container did not start within ${MAX_WAIT}s"
        exit 1
    fi
done
log "${OK_ICON} smallstep container is running"

# Wait until /home/step/certs/root_ca.crt exists inside 'smallstep' container
warn "${WAIT_ICON} Waiting for root_ca.crt to be created in smallstep container..."
SECONDS_WAITED=0
while ! docker exec smallstep test -f /home/step/certs/root_ca.crt 2>/dev/null; do
    sleep 1
    SECONDS_WAITED=$((SECONDS_WAITED+1))
    if [ "$SECONDS_WAITED" -ge "$MAX_WAIT" ]; then
        error "${ERR_ICON} Timeout: File not found after ${MAX_WAIT}s"
        exit 1
    fi
done
log "${OK_ICON} File found: /home/step/certs/root_ca.crt"

bash $SCRIPT_DIR/infra/smallstep/after-ca.sh
log "${OK_ICON} Smallstep CA is running"

## === 4. Start Ansible container ========================================
warn "[4/11] Starting Ansible container..."
docker compose up -d ansible
log "${OK_ICON} Ansible container is running"

# --- Elevation notice ---
info " ${LOCK_ICON} Steps 5 and 6 require elevation   "

## === 5. Create Ansible user ============================================
warn "[5/11] Creating Ansible user..."
sudo SUDOERS_CONTENT="$SUDOERS_CONTENT" bash $SCRIPT_DIR/scripts/01-create-ansible-user.sh
log "${OK_ICON} Ansible user creation step completed"

## === 6. Test ANSIBLE operability =======================================
warn "[6/11] Smoke test over [hostsrv]..."

# Wait until /inventories/lab/hosts.ini exists inside 'ansible' container
SECONDS_WAITED=0
warn "${WAIT_ICON} Waiting for inventory file to be created in ansible container..."
while ! docker exec ansible test -f /inventories/lab/hosts.ini 2>/dev/null; do
    sleep 1
    SECONDS_WAITED=$((SECONDS_WAITED+1))
    if [ "$SECONDS_WAITED" -ge "$MAX_WAIT" ]; then
        error "${ERR_ICON} Timeout: File not found after ${MAX_WAIT}s"
        exit 1
    fi
done
log "${OK_ICON} File found: /inventories/lab/hosts.ini"

# Launch the test
docker exec ansible ansible-playbook /playbooks/target_test.yml --limit hostsrv
if [ $? -ne 0 ]; then
    error "${ERR_ICON} Smoke test failed — stopping."
    exit 1
fi
log "${OK_ICON} Smoke test to HOSTSRV succeded "

## === 7. Run Ansible playbooks to create k8s infra ======================
warn "[7/11] Running Ansible k8s playbooks in [hostsrv]..."
docker exec ansible ansible-playbook $PLAYBOOK_DEBUG \
    /playbooks/jit_wrapper.yml --limit hostsrv \
    -e playbook_file="tasks-k8snodes/100-k8snodes-deploy.yml"
log "${OK_ICON} K8s nodes deploy completed"

## === 8. Run Ansible playbook to test connection to new k8s nodes =======
warn "[8/11] Smoke test over [k8snodes]..."
docker exec ansible ansible-playbook /playbooks/target_test.yml --limit k8snodes
if [ $? -ne 0 ]; then
    error "${ERR_ICON} Smoke test failed — stopping."
    exit 1
fi
log "${OK_ICON} Smoke test on K8SNODES succeded"

## === 9. Prepare VMs to host Kubernetes =================================
warn "[9/11] Preparing VMs to host Kubernetes..."
docker exec ansible ansible-playbook $PLAYBOOK_DEBUG \
    /playbooks/jit_wrapper.yml --limit k8snodes \
   -e playbook_file="tasks-k8snodes/200-k8snodes-setup.yml"

log "${OK_ICON} Kubernetes setup completed successfully"

## === 10. Installing applications on Kubernetes =========================
warn "[10/11] Cluster startup and install required tools"
docker exec ansible ansible-playbook $PLAYBOOK_DEBUG \
    /playbooks/jit_wrapper.yml --limit k8snodes \
   -e playbook_file="tasks-k8snodes/300-k8snodes-cluster.yml"

log "${OK_ICON} Kubernetes setup completed..."

warn "Extracting .kube/config from master node..."
EPHUSR=$(docker exec ansible ls -S -tc /root/.ansible/tmp/ | head -n 1)
mkdir -p $HOME/.kube
docker exec ansible scp \
  -i /root/.ansible/tmp/$EPHUSR/id_ed25519 \
  -o CertificateFile=/root/.ansible/tmp/$EPHUSR/id_ed25519-cert.pub \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  $EPHUSR@k8s-master:/home/$EPHUSR/.kube/config \
  /tmp/kubeconfig

docker cp ansible:/tmp/kubeconfig $HOME/.kube/config

docker exec ansible rm -rf /tmp/kubeconfig

## === 11. Proxy and other docker services ===============================
warn "[11/11] Upraising rest of docker containers..."
docker compose up -d proxy jenkins gitea registry
log "${OK_ICON} Full docker infrastructure deployed..."


## === 12. Check if all docker requisites are installed ===================
# sleep 30
warn "[12/11] Deploying telemetry namespace elements..."
bash $SCRIPT_DIR/scripts/02-deploy-telemetry.sh


log "\n\n\n ${OK_ICON} Applications deployed successfully"

title "${OK_ICON} Lab Environment Setup Complete"
