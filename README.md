🛡️ Swarm Hardening and Setup Guide
📘 Overview
This guide explains how to securely set up a Docker Swarm cluster on Ubuntu servers with best practices for basic hardening, remote GitLab CI deployment, and private management access using ZeroTier and TLS-secured Docker API.

It covers:

🔐 Hardening SSH and limiting remote access

🐳 Setting up Docker and initializing Swarm

🌐 Enabling GitLab CI to deploy over SSH tunnel + TLS

🧑‍💻 Restricting management to a ZeroTier private network

🛡️ Configuring UFW firewall

📜 SSL/TLS setup for Docker Remote API

⚠️ Disclaimer: This is a baseline guide. You should adapt hardening and firewall rules to your specific threat model and deployment requirements.

![Diagram of the architecutre](https://gitlab.com/bytemakers/swarm-hardening-and-setup-guide/assets/images/cx-diagram.svg)


🛠️ Initial Server Setup
✅ Update the System
bash
Copy
Edit
sudo apt update && sudo apt upgrade -y
✅ Install Required Packages
bash
Copy
Edit
sudo apt install -y curl gnupg2 ca-certificates lsb-release ufw fail2ban
🐳 Docker Installation and Swarm Init
✅ Install Docker Engine
bash
Copy
Edit
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
sudo apt install docker-compose-plugin -y
sudo usermod -aG docker $USER
✅ Initialize Docker Swarm
bash
Copy
Edit
docker swarm init
🌐 Install and Configure ZeroTier
✅ Install ZeroTier
bash
Copy
Edit
curl -s https://install.zerotier.com | sudo bash
sudo systemctl enable --now zerotier-one
sudo zerotier-cli join <your-network-id>
👤 Create GitLab CI Deploy User
bash
Copy
Edit
sudo adduser ci-deploy --disabled-password --gecos ""
sudo usermod -aG docker ci-deploy
🔐 Setup SSH Key for CI
Generate key pair and add the public key to the server:

bash
Copy
Edit
ssh-keygen -t rsa -b 4096 -C "ci-deploy"
bash
Copy
Edit
sudo mkdir -p /home/ci-deploy/.ssh
sudo nano /home/ci-deploy/.ssh/authorized_keys  # Paste key here
sudo chown -R ci-deploy:ci-deploy /home/ci-deploy/.ssh
sudo chmod 700 /home/ci-deploy/.ssh
sudo chmod 600 /home/ci-deploy/.ssh/authorized_keys
🔐 SSH Hardening (Tunnel-Only for CI)
✍️ Edit Authorized Key Format
Edit /home/ci-deploy/.ssh/authorized_keys:

text
Copy
Edit
command="echo 'Tunnel only'",no-pty,no-agent-forwarding,no-X11-forwarding,permitopen="127.0.0.1:2376" ssh-rsa AAAA...
🌍 Get Network Information (Public and ZeroTier)
Run this script to gather interface and CIDR info:

<details> <summary>📜 Click to View Script</summary>
bash
Copy
Edit
# (Paste the script you already have here — unchanged)
</details>
🛡️ Restrict SSH Access Based on Network
🗂️ Edit: /etc/ssh/sshd_config.d/ci-deploy.conf
text
Copy
Edit
# Allow full SSH from ZeroTier
Match Address 10.0.0.0/24  # Replace with your ZeroTier CIDR
    AllowUsers *

# Allow CI user only from non-ZeroTier networks
Match Address *,!10.0.0.0/24
    AllowUsers ci-deploy

# Force restrictions on CI user
Match User ci-deploy
    X11Forwarding no
    AllowTcpForwarding yes
    PermitTTY no
    ForceCommand echo "Tunnel only"
🔒 Enable Docker Remote API over TLS (for CI Deploy)
🧾 Create TLS Certificates
bash
Copy
Edit
mkdir -p ~/docker-certs && cd ~/docker-certs

openssl genrsa -aes256 -out ca-key.pem 4096
openssl req -new -x509 -days 365 -key ca-key.pem -sha256 -out ca.pem

openssl genrsa -out server-key.pem 4096
openssl req -subj "/CN=$(hostname)" -new -key server-key.pem -out server.csr

echo subjectAltName = IP:127.0.0.1,IP:<YOUR_PUBLIC_IP> > extfile.cnf
echo extendedKeyUsage = serverAuth >> extfile.cnf

openssl x509 -req -days 365 -sha256 -in server.csr -CA ca.pem -CAkey ca-key.pem \
  -CAcreateserial -out server-cert.pem -extfile extfile.cnf
📁 Install Certificates
bash
Copy
Edit
sudo mkdir -p /etc/docker/certs
sudo cp ca.pem server-cert.pem server-key.pem /etc/docker/certs/
sudo chown root:root /etc/docker/certs/*
sudo chmod 644 /etc/docker/certs/ca.pem
sudo chmod 644 /etc/docker/certs/server-cert.pem
sudo chmod 600 /etc/docker/certs/server-key.pem
🧰 Configure Docker Daemon
Create service override:

bash
Copy
Edit
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo nano /etc/systemd/system/docker.service.d/override.conf
ini
Copy
Edit
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd
Edit /etc/docker/daemon.json:

json
Copy
Edit
{
  "hosts": ["unix:///var/run/docker.sock", "tcp://0.0.0.0:2376"],
  "tls": true,
  "tlsverify": true,
  "tlscacert": "/etc/docker/certs/ca.pem",
  "tlscert": "/etc/docker/certs/server-cert.pem",
  "tlskey": "/etc/docker/certs/server-key.pem"
}
bash
Copy
Edit
sudo systemctl daemon-reload
sudo systemctl restart docker
🔥 Configure UFW Firewall
Update this script with your interfaces:

<details> <summary>📜 Click to View Script</summary>
bash
Copy
Edit
#!/bin/bash

# Variables
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
</details>
✅ Final Checklist
Step	Status
System updated	✅
Docker installed & swarm	✅
ZeroTier joined	✅
CI user created	✅
SSH restricted properly	✅
Docker TLS API enabled	✅
Firewall configured	✅