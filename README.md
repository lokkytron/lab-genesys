# 🏗️ LAB DevOps Project

## 📌 Overview

Welcome to **LAB-GENESYS**, a hands-on, break-it-fix-it, hack-friendly DevOps playground.  
This project spins up a **fully automated hybrid lab** where **Docker**, **Kubernetes**, **Ansible**, and **Libvirt** collide to create a real-world, chaos-tolerant environment for experimentation.

Everything deploys on a **single bare-metal host**, building a self-contained ecosystem where you can explore CI/CD pipelines, TLS-secured services, internal CA management, infrastructure automation, and full observability stacks—without touching production or cloud resources.

The lab was originally designed and tested on a machine with **8 CPU cores** and **20 GiB RAM**.  
It *can* run on smaller hardware, but you'll need to trim nodes, disable monitoring components, or scale down RAM/CPU manually.

> ⚠️ **Disclaimer:** This setup is intentionally opinionated, experimental, and optimized for learning—not for production.  
> Use it to push tools to their limits, break cluster states, and rebuild from scratch.

---

### 🎯 Purpose

This project exists for one reason:  
🔥 **After years of reinventing this lab by hand, it's finally automated—ready to unleash, abuse, test, and master DevOps tools in this sandbox.**

It gives you a place to:
- Boot and configure Kubernetes clusters from scratch
- Automate infrastructure with Ansible + cloud-init
- Build and operate Docker-based core services
- Deploy monitoring/log aggregation (Prometheus, Loki, Grafana...)
- Test GitOps + CI/CD flows with Gitea, Jenkins, and registry integration
- Experiment with TLS certificates and internal PKI
- Simulate real-world networking flows, ingress routing, and service exposure

The goal isn't perfection—it's **practice**, **iteration**, and **curiosity**.
This lab is my personal DevOps arena… feel free to claim it as your battleground too

---

## 🗂️  Project Structure
├── apps/ # Application source code or demo apps to deploy
├── dockerdata/ # Persistent data volumes for containers
├── infra/ # Infrastructure provisioning and Kubernetes playbooks
├── scripts/ # Additional scripts for automation or management
├── .env.template # Template for environment variables
├── .gitignore # Files to exclude from Git
├── docker-compose.yml # Docker services stack (proxy, CI/CD, registry, etc.)
└── genesys.sh # Main deployment/automation script


---

## ⚙️  Components

- **Docker Containers**: Proxy, CoreDNS, CI/CD stack (Jenkins, Gitea), Smallstep CA, Registry
- **Libvirt VMs**: Kubernetes control-plane and worker nodes
- **Kubernetes Cluster**: Includes NGINX Ingress Controller, MetalLB, Flannel CNI, Local-path storage, monitoring & logging stack
- **Automation**:
  - `genesys.sh` orchestrates environment deployment
  - Ansible playbooks in `infra/` handle VM preparation, K8s setup, and application deployment

---

## 🚀 Deployment

1. Prepare host machine with required packages and network configuration
2. If you want to change VMs names or network ranges to fit in your infra, update /.genesys.sh with your environment settings
3. Run the main deployment script:

```bash
./genesys.sh

This will:
-Perform envsubst of several template files
-Deploy Docker containers and volumes
-Provision Libvirt VMs for Kubernetes nodes
-Bootstrap Kubernetes cluster
-Deploy core services, ingress, and monitoring stack

## 🔧 Next Steps

-This laboratory will be always able to receive improvements, so you can consider this is a WIP
-The roadmap in mind, while I am writing this lines should be:
  -Improved documentation with the full workflow of the LAB deployment
  -Harden environment (cluster, Docker, networking)
  -Prepare a demo application
  -Integrate CI/CD pipelines (Jenkins + Gitea + ArgoCD)
  -Execute automated integration tests and performance tests
  -Configure automatic deployments triggered by Docker Registry updates when tests succeed.

## 📖 References

See infra/README.md for detailed lab infrastructure information
