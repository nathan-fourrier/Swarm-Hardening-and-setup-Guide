# Swarm Hardening and setup Guide

## Update the server

``` bash
sudo apt update && sudo apt upgrade -y
```

## Install fail2ban

``` bash
sudo apt install -y curl gnupg2 ca-certificates lsb-release ufw fail2ban
```

## Install Docker

``` bash
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
```

``` bash
sudo apt install docker-compose-plugin -y
```

``` bash
sudo usermod -aG docker $USER
```

## Init swarm

``` bash
docker swarm init
```

## Install zerotier

```bash
url -s https://install.zerotier.com | sudo bash
````

``` bash
sudo systemctl enable --now zerotier-one
````

``` bash
sudo zerotier-cli join <your-network-id>
````

## Create deploy user

```bash
sudo adduser ci-deploy --disabled-password --gecos ""
```

```bash
sudo usermod -aG docker ci-deploy
````

```bash
sudo mkdir -p /home/ci-deploy/.ssh
sudo nano /home/ci-deploy/.ssh/authorized_keys # paste public key
sudo chown -R ci-deploy:ci-deploy /home/ci-deploy/.ssh
sudo chmod 700 /home/ci-deploy/.ssh
sudo chmod 600 /home/ci-deploy/.ssh/authorized_keys
```

## Hardening ssh

Edit /home/ci-deploy/.ssh/authorized_keys to match this format

```
command="echo 'Tunnel only'",no-pty,no-agent-forwarding,no-X11-forwarding,permitopen="127.0.0.1:2376" ssh-ed25519 A.....
```
Edit /etc/ssh/sshd_config.d/ci-deploy.conf

```
Match Address 10.0.0.0/24 # Replace by zerotier network
        AllowUsers *
Match Address *,!10.0.0.0/24 # Replace by zerotier network
	AllowUsers ci-deploy

Match User ci-deploy
        X11Forwarding no
        AllowTcpForwarding yes
        PermitTTY no
        ForceCommand echo "Tunnel only"

```
## Enable docker api ssl 

Create CA + Certs for daemon and client

``` bash
mkdir -p ~/docker-certs && cd ~/docker-certs
openssl genrsa -aes256 -out ca-key.pem 4096
openssl req -new -x509 -days 365 -key ca-key.pem -sha256 -out ca.pem

# Serveur cert
openssl genrsa -out server-key.pem 4096
openssl req -subj "/CN=$(hostname)" -new -key server-key.pem -out server.csr

echo subjectAltName = IP:127.0.0.1,IP:<YOUR_PUBLIC_IP> > extfile.cnf
echo extendedKeyUsage = serverAuth >> extfile.cnf

openssl x509 -req -days 365 -sha256 -in server.csr -CA ca.pem -CAkey ca-key.pem \
  -CAcreateserial -out server-cert.pem -extfile extfile.cnf
```

Configure daemon

```bash
sudo mkdir -p /etc/docker/certs
sudo cp ca.pem server-cert.pem server-key.pem /etc/docker/certs/

sudo nano /etc/docker/daemon.json
```

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
sudo systemctl restart docker
```
## Configure firewall

Script to configure ufw

```bash
#!/bin/bash

# Variables
PUB_IFACE="ens3"                  # Replace by public inteface
ZT_IFACE="ztr2qxgeyd"             # Replace by zerotier interface
ALLOWED_SSH_IP="146.59.198.37"    # Public IP

echo "[1/6] Reset UFW..."
ufw --force reset

echo "[2/6] Define default policies..."
ufw default deny incoming
ufw default allow outgoing
ufw default deny forward

echo "[3/6] Allow HTTP/HTTPS on public interfaces..."
ufw allow in on $PUB_IFACE to any port 80 proto tcp
ufw allow in on $PUB_IFACE to any port 443 proto tcp

echo "[4/6] Allow ssh..."
ufw allow in on $PUB_IFACE to any port 22 proto tcp

echo "[5/6] Allow all on zerotier if..."
ufw allow in on $ZT_IFACE
ufw allow out on $ZT_IFACE

echo "[6/6] Enable UFW..."
ufw --force enable

echo "[✅] UFW configuration done."
ufw status verbose

```
