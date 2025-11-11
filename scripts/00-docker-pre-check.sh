#!/usr/bin/env bash
# 00-docker-pre-check.sh
# Checks if Docker engine and compose plugin are installed (Debian/Ubuntu family).
# Installs if missing.

set -e

YELLOW="\e[33m"
GREEN="\e[32m"
RED="\e[31m"
RESET="\e[0m"

echo -e "${YELLOW}[Pre-Check] Checking Docker prerequisites...${RESET}"

# Function to list installed docker-related packages
list_installed_docker_packages() {
    echo -e "${YELLOW}--- Installed docker-related packages ---${RESET}"
    dpkg -l | grep -Ei 'docker|containerd' || echo "No docker-related packages found."
    echo -e "${YELLOW}----------------------------------------${RESET}"
}

# Function to check if docker engine and compose plugin exist and run
docker_requirements_met() {
    if command -v docker >/dev/null 2>&1 \
       && docker info >/dev/null 2>&1 \
       && docker compose version >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Check
if docker_requirements_met; then
    echo -e "${GREEN}✔ Docker engine and compose plugin already installed and running.${RESET}"
else
    echo -e "${RED}❌ Docker or compose plugin missing. Installing required packages...${RESET}"

    list_installed_docker_packages

    # --- Elevation notice ---
    echo -e "${CYAN}========================================${RESET}"
    echo -e "${CYAN}   🔒 APT operations require elevation   ${RESET}"
    echo -e "${CYAN}========================================${RESET}"

    sudo apt-get update

    sudo apt-get install -y docker-ce docker-ce-cli docker-buildx-plugin docker-compose-plugin

    echo -e "${GREEN}✔ Docker packages installation completed.${RESET}"

    # Optionally ensure docker service is started/enabled
    if ! systemctl is-active --quiet docker; then
        sudo systemctl start docker
        sudo systemctl enable docker
        echo -e "${GREEN}✔ Docker service started and enabled.${RESET}"
    fi

fi

# Docker networking
# Check if the network already exists
if ! docker network ls --format '{{.Name}}' | grep -q "^${DOCKER_NETWORK_NAME}$"; then
    echo "Creating Docker network '${DOCKER_NETWORK_NAME}' with bridge '${DOCKER_BRIDGE_NAME}'..."
    docker network create \
        --driver=bridge \
        --opt "com.docker.network.bridge.name"="${DOCKER_BRIDGE_NAME}" \
        --subnet="${DOCKER_SUBNET}" \
        --gateway="${DOCKER_GATEWAY}" \
        "${DOCKER_NETWORK_NAME}"
else
    echo "Docker network '${DOCKER_NETWORK_NAME}' already exists. Skipping creation."
fi
