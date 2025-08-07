# Swarm Hardening and Setup Guide

## Overview

This guide explains how to securely set up a Docker Swarm cluster on Ubuntu servers with best practices for basic hardening, remote GitLab CI deployment, and private management access using ZeroTier and TLS-secured Docker API.

It covers:

- Hardening SSH and limiting remote access
- Setting up Docker and initializing Swarm
- Enabling GitLab CI to deploy over SSH tunnel + TLS
- Restricting management to a ZeroTier private network
- Configuring UFW firewall
- SSL/TLS setup for Docker Remote API
- Setting up traefik
- Setting up portainer

> Disclaimer: This is a baseline guide. You should adapt hardening and firewall rules to your specific threat model and deployment requirements.

![Diagram of the Architecture](./assets/images/cx-diagram.png)

---

## Initial Server Setup

### Update the System

```bash
sudo apt update && sudo apt upgrade -y
```

### Install Required Packages

```bash
sudo apt install -y curl gnupg2 ca-certificates lsb-release ufw fail2ban
```

---

## Docker Installation and Swarm Init

### Install Docker Engine

```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
sudo apt install docker-compose-plugin -y
sudo usermod -aG docker $USER
```

### Initialize Docker Swarm

```bash
docker swarm init
```

---

## Install and Configure ZeroTier

### Create ZeroTier Network

Before installing ZeroTier on your servers, you need to create a private network through the ZeroTier web interface:

1. **Sign up/Login to ZeroTier Central**
   - Go to [my.zerotier.com](https://my.zerotier.com)
   - Create an account or login to your existing account

2. **Create a New Network**
   - Click "Create" or "Create Network"
   - Choose "Private Network" (recommended for security)
   - Give your network a descriptive name (e.g., "Docker Swarm Management")

3. **Configure Network Settings**
   - **Network ID**: Note the 16-character network ID (e.g., `8056c2e21c000001`)
   - **Access Control**: Set to "Private" for enhanced security
   - **IPv4 Auto-Assign**: Enable and configure your desired subnet (e.g., `10.0.0.0/24`)
   - **IPv6 Auto-Assign**: Optional, can be disabled if not needed

4. **Advanced Settings** (Optional)
   - **Route Management**: Enable if you want ZeroTier to manage routes
   - **Bridge Mode**: Disable unless you need to bridge to physical networks
   - **DNS**: Configure custom DNS servers if needed

5. **Save the Network**
   - Click "Save" to create your network
   - Keep the Network ID handy - you'll need it for joining servers

### Install ZeroTier

```bash
curl -s https://install.zerotier.com | sudo bash
sudo systemctl enable --now zerotier-one
sudo zerotier-cli join <your-network-id>
```

> **Note**: Replace `<your-network-id>` with the 16-character network ID from step 3 above.

---

## Create GitLab CI Deploy User

```bash
sudo adduser ci-deploy --disabled-password --gecos ""
sudo usermod -aG docker ci-deploy
```

### Setup SSH Key for CI

Generate key pair and add the public key to the server:

```bash
ssh-keygen -t rsa -b 4096 -C "ci-deploy"
```

```bash
sudo mkdir -p /home/ci-deploy/.ssh
sudo nano /home/ci-deploy/.ssh/authorized_keys
sudo chown -R ci-deploy:ci-deploy /home/ci-deploy/.ssh
sudo chmod 700 /home/ci-deploy/.ssh
sudo chmod 600 /home/ci-deploy/.ssh/authorized_keys
```

---

## SSH Hardening (Tunnel-Only for CI)

### Edit Authorized Key Format

Edit `/home/ci-deploy/.ssh/authorized_keys`:

```
command="echo 'Tunnel only'",no-pty,no-agent-forwarding,no-X11-forwarding,permitopen="127.0.0.1:2376" ssh-rsa AAAA...
```

---

## Get Network Information (Public and ZeroTier)

Run this script to gather interface and CIDR info:

```bash
#!/bin/bash

# Function to calculate network CIDR from IP and prefix
calculate_network_cidr() {
    ip_with_prefix=$1

    ip=${ip_with_prefix%/*}
    prefix=${ip_with_prefix#*/}

    IFS='.' read -r i1 i2 i3 i4 <<< "$ip"

    # Convert IP to integer
    ip_int=$(( (i1 << 24) + (i2 << 16) + (i3 << 8) + i4 ))

    # Build subnet mask
    mask=$(( 0xFFFFFFFF << (32 - prefix) & 0xFFFFFFFF ))

    # Calculate network
    network=$(( ip_int & mask ))

    n1=$(( (network >> 24) & 0xFF ))
    n2=$(( (network >> 16) & 0xFF ))
    n3=$(( (network >> 8) & 0xFF ))
    n4=$(( network & 0xFF ))

    echo "$n1.$n2.$n3.$n4/$prefix"
}

echo "=== ZeroTier Info ==="
zt_iface=$(ip -o link show | awk -F': ' '/zt/{print $2}' | head -n1)

if [ -n "$zt_iface" ]; then
    zt_ip_cidr=$(ip -4 addr show dev "$zt_iface" | awk '/inet / {print $2}')
    zt_ip=${zt_ip_cidr%/*}
    zt_network_id=$(sudo zerotier-cli listnetworks | grep "$zt_iface" | awk '{print $3}')
    zt_network_cidr=$(calculate_network_cidr "$zt_ip_cidr")

    echo "Interface   : $zt_iface"
    echo "IP Address  : $zt_ip"
    echo "Network CIDR: $zt_network_cidr"
    echo "Network ID  : $zt_network_id"
else
    echo "No ZeroTier interface found."
fi

echo ""
echo "=== Public Interface Info ==="
public_iface=$(ip route get 1.1.1.1 | grep -oP 'dev \K\S+')

if [ -n "$public_iface" ]; then
    public_ip_cidr=$(ip -4 addr show dev "$public_iface" | awk '/inet / {print $2}')
    public_ip=${public_ip_cidr%/*}
    public_network_cidr=$(calculate_network_cidr "$public_ip_cidr")

    echo "Interface   : $public_iface"
    echo "IP Address  : $public_ip"
    echo "Network CIDR: $public_network_cidr"
else
    echo "No public interface found."
fi
```

---

## Restrict SSH Access Based on Network

### Edit: `/etc/ssh/sshd_config.d/ci-deploy.conf`

```text
Match Address 10.0.0.0/24 # Replace by zerotier CIDR network
    AllowUsers *

Match Address *,!10.0.0.0/24 # Replace by zerotier CIDR network
    AllowUsers ci-deploy

Match User ci-deploy
    X11Forwarding no
    AllowTcpForwarding yes
    PermitTTY no
    ForceCommand echo "Tunnel only"
```

---

## Enable Docker Remote API over TLS

### Create TLS Certificates

```bash
mkdir -p ~/docker-certs && cd ~/docker-certs
openssl genrsa -aes256 -out ca-key.pem 4096
openssl req -new -x509 -days 365 -key ca-key.pem -sha256 -out ca.pem

openssl genrsa -out server-key.pem 4096
openssl req -subj "/CN=$(hostname)" -new -key server-key.pem -out server.csr

echo subjectAltName = IP:127.0.0.1,IP:<YOUR_PUBLIC_IP> > extfile.cnf
echo extendedKeyUsage = serverAuth >> extfile.cnf

openssl x509 -req -days 365 -sha256 -in server.csr -CA ca.pem -CAkey ca-key.pem \
  -CAcreateserial -out server-cert.pem -extfile extfile.cnf

# Client cert
openssl genrsa -out client-key.pem 4096
openssl req -subj '/CN=client' -new -key client-key.pem -out client.csr

echo extendedKeyUsage = clientAuth > extfile-client.cnf

openssl x509 -req -days 365 -sha256 -in client.csr -CA ca.pem -CAkey ca-key.pem \
  -CAcreateserial -out client-cert.pem -extfile extfile-client.cnf
```

> Note:
> - ca-key.pem: Private CA key (keep secret)
> - ca.pem: Public CA cert
> - server-key.pem: Docker server key
> - server-cert.pem: Docker server cert
> - key.pem – Client private key (keep safe)
> - cert.pem – Client certificate
> - server.csr, ca.srl, extfile.cnf, extfile-client.cnf, client.csr: optional to delete

### Install Certificates

```bash
sudo mkdir -p /etc/docker/certs
sudo cp ca.pem server-cert.pem server-key.pem /etc/docker/certs/
sudo chown root:root /etc/docker/certs/*
sudo chmod 644 /etc/docker/certs/ca.pem
sudo chmod 644 /etc/docker/certs/server-cert.pem
sudo chmod 600 /etc/docker/certs/server-key.pem
```

### Configure Docker Daemon

```bash
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo nano /etc/systemd/system/docker.service.d/override.conf
```

```
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd
```

Edit `/etc/docker/daemon.json`:

```json
{
  "hosts": ["unix:///var/run/docker.sock", "tcp://0.0.0.0:2376"],
  "tls": true,
  "tlsverify": true,
  "tlscacert": "/etc/docker/certs/ca.pem",
  "tlscert": "/etc/docker/certs/server-cert.pem",
  "tlskey": "/etc/docker/certs/server-key.pem"
}
```

```bash
sudo systemctl daemon-reload
sudo systemctl restart docker
```

---

## Configure UFW Firewall

```bash
#!/bin/bash

PUB_IFACE="ens3"         # Replace with public interface
ZT_IFACE="ztr2qxgeyd"    # Replace with ZeroTier interface

echo "[1/6] Reset UFW..."
ufw --force reset

echo "[2/6] Define default policies..."
ufw default deny incoming
ufw default allow outgoing
ufw default deny forward

echo "[3/6] Allow HTTP/HTTPS on public interfaces..."
ufw allow in on $PUB_IFACE to any port 80 proto tcp
ufw allow in on $PUB_IFACE to any port 443 proto tcp

echo "[4/6] Allow SSH..."
ufw allow in on $PUB_IFACE to any port 22 proto tcp

echo "[5/6] Allow all traffic on ZeroTier interface..."
ufw allow in on $ZT_IFACE
ufw allow out on $ZT_IFACE

echo "[6/6] Enable UFW..."
ufw --force enable
ufw status verbose
```

---

## Deploying traefik using ci

We are going to setup the traefik stack using a gitlab repo and ci to check the full process of deployment

### Step 1: Set Up CI/CD Variables at Group Level

Navigate to your GitLab group settings and configure the following CI/CD variables:

#### Required Variables:

**SSH Connection Variables:**
- `VPS_SSH_PRIVATE_KEY`: Private SSH key for connecting to your VPS (the private key corresponding to the public key added to ci-deploy user)
- `VPS_SSH_KNOWN_HOSTS`: SSH known hosts file content for your VPS (run `ssh-keyscan -H your-vps-ip` to get this)
- `VPS_SSH_USER`: SSH username on your VPS (should be `ci-deploy`)
- `VPS_IP`: Public IP address of your VPS

**Docker TLS Certificate Variables:**
- `DOCKER_SWARM_CA`: Content of the CA certificate file (`ca.pem`) - used to verify the Docker daemon's TLS certificate
- `RUNNER_DOCKER_CERT`: Content of the client certificate file (`client-cert.pem`) - used for client authentication to Docker daemon
- `RUNNER_DOCKER_CERT_KEY`: Content of the client private key file (`client-key.pem`) - used for client authentication to Docker daemon


#### Variable Descriptions:

| Variable | Description | Type | Protected | Masked |
|----------|-------------|------|-----------|--------|
| `VPS_SSH_PRIVATE_KEY` | Private SSH key for secure connection to VPS | Variable | No | Yes |
| `VPS_SSH_KNOWN_HOSTS` | SSH known hosts to prevent man-in-the-middle attacks | Variable | No | No |
| `VPS_SSH_USER` | SSH username on the VPS (ci-deploy user) | Variable | No | No |
| `VPS_IP` | Public IP address of your VPS server | Variable | No | No |
| `DOCKER_SWARM_CA` | CA certificate for Docker TLS verification | Variable | No | Yes |
| `RUNNER_DOCKER_CERT` | Client certificate for Docker TLS authentication | Variable | No | Yes |
| `RUNNER_DOCKER_CERT_KEY` | Client private key for Docker TLS authentication | Variable | No | Yes |


**Security Notes:**
- Mark sensitive variables (passwords, keys, certificates) as "Masked" to prevent them from appearing in job logs
- Consider marking production variables as "Protected" if you have separate environments
- Store the actual certificate and key files securely and copy their contents into the variables

### Step 2: Create a "Runners" Project for CI Templates

First, create a new GitLab project called "runners" (or any name you prefer) to store your CI/CD templates. This project will serve as a central repository for reusable CI configurations.

1. Go to your GitLab group and create a new project named "runners"
2. Clone the project locally
3. Copy the `swarm-deployment.yml` template to this project:

```bash
git clone <your-group>/runners.git
cd runners
# Copy the swarm-deployment.yml from this guide's assets/config/ directory
```

The `swarm-deployment.yml` file contains reusable CI/CD templates that define:
- Build stages for Docker images
- Deploy stages for Docker Swarm stacks
- SSH tunnel setup for secure remote deployment
- Docker TLS certificate handling

### Step 3: Create Traefik Repository

Create a new GitLab project for your Traefik deployment:

1. Create a new project named "traefik" in your GitLab group
2. Clone the project locally
3. Copy the `traefik_stack.yml` in the folder stacks of your traefik project (and edit fields for your domain name)
4. Copy the `traefik.gitlab-ci.yml` as `gitlab-ci.yml` in the root of your traefik project
5. Update the include section to reference your actual runners project:

```yaml
include:
  - project: 'your-group/runners'  # Replace with your actual project path
    ref: main
    file: "swarm-deployment.yml"
```

### Step 4: Create Traefik Public Network

In the specific case of traefik, before deploying the stack, you need to create the `traefik-public` network that Traefik will use to communicate with other services:

```bash
# Create the traefik-public network
docker network create --driver overlay --attachable traefik-public
```

This network will be used by Traefik to discover and route traffic to other services in your Swarm. The `--attachable` flag allows standalone containers to connect to this overlay network.



