#!/bin/bash

NETWORK_NAME="infralocal"
BRIDGE_NAME="br_infralocal"
SUBNET="172.25.0.0/16"
GATEWAY="172.25.0.1"

# Check if the network already exists
if ! docker network ls --format '{{.Name}}' | grep -q "^${NETWORK_NAME}$"; then
    echo "Creating Docker network '${NETWORK_NAME}' with bridge '${BRIDGE_NAME}'..."
    docker network create \
        --driver=bridge \
        --opt "com.docker.network.bridge.name"="${BRIDGE_NAME}" \
        --subnet="${SUBNET}" \
        --gateway="${GATEWAY}" \
        "${NETWORK_NAME}"
else
    echo "Docker network '${NETWORK_NAME}' already exists. Skipping creation."
fi
