# 🧪 Infrastructure LAB — Overview

## ✅ Current Status

- Full environment deployed using automated tooling  
- Ansible manages targets using ephemeral SSH certificate-based users  
- Docker services deployed + telemetry namespace in Kubernetes  
- Complete TLS integration across Kubernetes services and Docker services  
- Telemetry namespace deployed with Grafana, Prometheus, Loki, Promtail and more.

---

## 🧩 Components

### 🖥️ Host Machine

- **OS:** Debian 13  
- **Hostname:** `lab`  
- **Type:** Bare-metal  
- **CPU:** AMD Bulldozer — 8 cores  
- **RAM:** 20 GiB  
- **LAN IP:** `192.168.1.222`  
- **IP forwarding:** Enabled  

#### Virtualized Network Layers

##### 🔹 Libvirt
- Bridge: `br_labkvmnet`  
- VM Network Range: `192.168.5.0/24`  

##### 🔹 Docker
- Bridge: `br_labdockernet`  
- Network Range: `172.25.0.0/16`  

---

### 🐳 Docker Services

7 containers deployed via `docker-compose.yaml`

| Name      | Network       | Ports (host→container) | DNS Name          |
|-----------|---------------|-------------------------|-------------------|
| proxy     | host_mode     | 80 → 80                 | —                 |
| coredns   | host_mode     | 53 → 53                 | —                 |
| ansible   | host_mode     | —                       | —                 |
| jenkins   | br_infralocal | 8080 → 8080             | jenkins.lab.loc   |
| gitea     | br_infralocal | 3000 → 3000             | gitea.lab.loc     |
| registry  | br_infralocal | 5000 → 5000             | registry.lab.loc  |
| smallstep | br_infralocal | 9000 → 9000             | smallstep.lab.loc |

---

### 🖥️ Libvirt Virtual Machines

| Name        | OS         | CPU     | RAM   | IP              | Role           |
|-------------|------------|---------|-------|-----------------|----------------|
| k8s-master  | Ubuntu 24  | 2 cores | 4 GiB | 192.168.5.11    | control-plane  |
| k8s-worker1 | Ubuntu 24  | 2 cores | 3 GiB | 192.168.5.21    | worker         |
| k8s-worker2 | Ubuntu 24  | 2 cores | 3 GiB | 192.168.5.22    | worker         |

---

### ☸️ Kubernetes Cluster

- **Version:** 1.29  

#### Installed Components

- Flannel CNI  
- MetalLB LoadBalancer  
- NGINX Ingress Controller  
- Local Path Provisioner (StorageClass)  
- Ingress rules pointing to Docker-hosted applications  
- Monitoring + logging stack (telemetry namespace):  
  - Prometheus  
  - AlertManager  
  - Node Exporter  
  - Kube State Metrics  
  - Loki  
  - Promtail  
  - Grafana with customized dashboards  

---

## 🌐 Networking Flow

LAN Client → https://gitea.lab.loc
    ↓
Local DNS (CoreDNS) resolves domain → 192.168.1.222
    ↓
Host (proxy container in host-mode)
    ↓
proxy_pass → MetalLB IP: 192.168.5.2
    ↓
K8s NGINX Ingress Controller
    ↓
Ingress → Service → Endpoints → Docker gitea
    ↓
Gitea application responds to client


---

## 🎯 Project Goal

### 📌 Objective

Provide **fully automated, hybrid DevOps infrastructure** combining Docker + Kubernetes environments.

One execution script will:

- Deploy containers (CA, Ansible, DNS, proxy, CI/CD components)  
- Validate host requirements  
- Prepare cloud-init disks for VM provisioning  
- Create and configure K8s nodes via Libvirt  
- Initialize cluster with kubeadm  
- Deploy core Kubernetes services (CNI, ingress, LB, storage)  
- Deploy ingress rules for Docker services  
- Deploy monitoring and logging stack (Prometheus/Loki/Grafana)  

### 🚫 Manual Steps Required

- Router configuration to use CoreDNS as LAN DNS  
- Import root CA certificate into local browsers/devices  

### ✅ Final Result

A complete DevOps-ready environment with:

- CA issuing TLS + SSH certificates  
- Automated K8s provisioning via Ansible  
- CI/CD components (Jenkins + Gitea) online  
- External access using HTTPS for all services  

---

## ⚠️ Constraints & Challenges

- Hybrid network model → Docker and K8s in isolated networks  
- All LAN traffic enters through: `192.168.1.222`  
- CoreDNS (or `/etc/hosts`) required to resolve `*.lab.loc`  
- Proxy container forwards traffic to K8s ingress controller  
- Ingress routes traffic to pods or external services  
- Minimal iptables usage (only what Docker/Libvirt require)  
- Ansible uses just-in-time privileged accounts via SSH certificates  
- Same CA used for SSH certs and TLS issuance  

---

## 🔧 Next Steps (Roadmap)

- Harden environment (host, VMs, network layers, Docker, Kubernetes)  
- Deploy demo application (Nginx + PHP) automatically  
- Integrate Jenkins + Gitea for CI workflows  
- Install and configure ArgoCD  
  - Trigger sync on new registry image  
  - Deploy to isolated namespace  
- Implement automated load tests from Jenkins  
- Promote images after “green” tests  
- Remove the isolated test namespace
- Trigger progressive rollouts in Kubernetes  

---

