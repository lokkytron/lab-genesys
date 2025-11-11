# 🧹 DevOps LAB Cleanup – Docker & Libvirt

This document describes the **safe manual cleanup** of a Kubernetes LAB running on Debian 13, using Docker and Libvirt/KVM.

---

## 1. Stop Kubernetes LAB containers

1.Navigate to your LAB folder:

```bash
cd /path/to/your/LAB
```

2.Stop the LAB containers (via docker-compose):

```bash
docker compose down
```

3.Verify no other containers are running:

```bash
docker ps
```

- If no containers are shown → safe to uninstall Docker.  
- If other containers are running → **STOP here**. Investigate before uninstalling Docker.

---

## 2. Shut down and remove Kubernetes LAB virtual machines

1.List running VMs:

```bash
virsh list
```

2.If only these LAB VMs are running:

```txt
k8s-master
k8s-worker1
k8s-worker2
```

Proceed to destroy and undefine them:

```bash
sudo virsh destroy k8s-master   || true
sudo virsh undefine k8s-master  || true
sudo virsh destroy k8s-worker1  || true
sudo virsh undefine k8s-worker1 || true
sudo virsh destroy k8s-worker2  || true
sudo virsh undefine k8s-worker2 || true
```

3.Verify no other VMs remain:

```bash
virsh list --all
```

- If any non-LAB VMs exist → **STOP** — do not uninstall libvirt yet.

---

## 3. Remove any active libvirt networks

1.List networks:

```bash
virsh net-list
```

2.Destroy and undefine LAB-specific networks:

```bash
sudo virsh net-destroy <network_name>  || true
sudo virsh net-undefine <network_name> || true
```

3.Verify:

```bash
virsh net-list --all
```

---

## 4. Uninstall Docker, Containerd, Libvirt, QEMU, Virt-manager packages

Only proceed when:

- No Docker containers are running.
- No libvirt VMs are defined.
- No libvirt networks are active.

Run:

```bash
sudo apt-get update
sudo apt-get -y remove --purge docker-ce docker-ce-cli docker-compose-plugin \
  docker-buildx-plugin containerd.io \
  libvirt-daemon-system libvirt-clients virt-manager qemu-system-x86
sudo apt-get -y autoremove --purge
```

---

## 5. Remove orphaned folders and configs

Remove leftover data, configs, and state:

```bash
# Docker leftovers
sudo rm -rf /var/lib/docker
sudo rm -rf /etc/docker
sudo rm -rf /var/run/docker.sock

# Containerd leftovers
sudo rm -rf /var/lib/containerd

# Libvirt leftovers
sudo rm -rf /var/lib/libvirt
sudo rm -rf /etc/libvirt

# Optional: clean logs
sudo journalctl --rotate
sudo journalctl --vacuum-time=1d
```

---

## 6. Final verification

1.Confirm packages are gone:

```bash
dpkg -l | egrep 'docker|containerd|libvirt|qemu|virt'
```

- Should return no installed packages.

2.Confirm no containers, VMs, or networks exist.

3.Optionally reboot the host:

```bash
sudo reboot
```

---

✅ After these steps, your Debian host should be clean of all LAB-related Docker and Libvirt components, while preserving other user data and system configuration.

