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

> Disclaimer: This is a baseline guide. You should adapt hardening and firewall rules to your specific threat model and deployment requirements.

![Diagram of the Architecture](./assets/images/cx-diagram.svg)

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

### Install ZeroTier

```bash
curl -s https://install.zerotier.com | sudo bash
sudo systemctl enable --now zerotier-one
sudo zerotier-cli join <your-network-id>
```

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
```

> Note:
> - ca-key.pem: Private CA key (keep secret)
> - ca.pem: Public CA cert
> - server-key.pem: Docker server key
> - server-cert.pem: Docker server cert
> - server.csr, ca.srl, extfile.cnf: optional to delete

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

## Final Checklist

| Step                        | Status |
|-----------------------------|--------|
| System updated              | ✅      |
| Docker installed & swarm    | ✅      |
| ZeroTier joined             | ✅      |
| CI user created             | ✅      |
| SSH restricted properly     | ✅      |
| Docker TLS API enabled      | ✅      |
| Firewall configured         | ✅      |