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
```

Create an ssh keypair for the gitlab ci to login
```bash
ssh-keygen -t rsa -b 4096 -C "ci-deploy"
```

```bash
sudo mkdir -p /home/ci-deploy/.ssh
sudo nano /home/ci-deploy/.ssh/authorized_keys # paste public key previously generated
sudo chown -R ci-deploy:ci-deploy /home/ci-deploy/.ssh
sudo chmod 700 /home/ci-deploy/.ssh
sudo chmod 600 /home/ci-deploy/.ssh/authorized_keys
```

## Hardening ssh

Edit /home/ci-deploy/.ssh/authorized_keys to match this format

```
command="echo 'Tunnel only'",no-pty,no-agent-forwarding,no-X11-forwarding,permitopen="127.0.0.1:2376" ssh-ed25519 A.....
```
In the next steps you will need info for public interfaces and zerotier, so execute this script to get it.

``` bash
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

The script produces output similar to the following:

```bash
=== ZeroTier Info === 
Interface : ztmjflt6v5
IP Address: 10.34.65.21
Network CIDR: 10.34.65.0/24
Network ID: 8156d2e21c7b18a1

=== Public Interface Info ===
Interface : ens6
IP Address: 172.25.13.10
Network CIDR: 172.25.13.10/32
```

Edit /etc/ssh/sshd_config.d/ci-deploy.conf

```
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
## Enable docker api ssl 

Create CA + Certs for daemon and client

``` bash
mkdir -p ~/docker-certs && cd ~/docker-certs
# Choose a strong passphrase for the CA
openssl genrsa -aes256 -out ca-key.pem 4096
openssl req -new -x509 -days 365 -key ca-key.pem -sha256 -out ca.pem

# Server cert
openssl genrsa -out server-key.pem 4096
openssl req -subj "/CN=$(hostname)" -new -key server-key.pem -out server.csr

echo subjectAltName = IP:127.0.0.1,IP:<YOUR_PUBLIC_IP> > extfile.cnf
echo extendedKeyUsage = serverAuth >> extfile.cnf

openssl x509 -req -days 365 -sha256 -in server.csr -CA ca.pem -CAkey ca-key.pem \
  -CAcreateserial -out server-cert.pem -extfile extfile.cnf
```

> **📄 Note: Description of Generated Files**
>
> - **`ca-key.pem`**: Private key for the Certificate Authority (CA). **Keep this secret**.
> - **`ca.pem`**: Public certificate for the CA. Share this with clients to verify certificates.
> - **`ca.srl`**: Serial number tracker for the CA. Automatically created when signing certificates.
> - **`server-key.pem`**: Private key for the Docker server. **Keep this secret**.
> - **`server.csr`**: Certificate Signing Request for the server. Can be deleted after signing.
> - **`server-cert.pem`**: Signed certificate for the server. Used by Docker for TLS authentication.
> - **`extfile.cnf`**: OpenSSL config file specifying certificate extensions like `subjectAltName`. Reusable for future certs.
>
> ✅ **Keep Safe**: `ca-key.pem`, `server-key.pem`  
> ✅ **Server Needs**: `server-key.pem`, `server-cert.pem`, `ca.pem`  
> ✅ **Clients Need**: `ca.pem` to verify the server  
> 🗑️ **Optional to Delete**: `server.csr`, `ca.srl`, `extfile.cnf`


Configure daemon

```bash
sudo mkdir -p /etc/docker/certs
sudo cp ca.pem server-cert.pem server-key.pem /etc/docker/certs/
sudo chown root:root /etc/docker/certs/*

# Set permissions
sudo chmod 644 /etc/docker/certs/ca.pem
sudo chmod 644 /etc/docker/certs/server-cert.pem
sudo chmod 600 /etc/docker/certs/server-key.pem
```

Move daemon config to json

``` bash
# Create the directory to override service config
sudo mkdir -p /etc/systemd/system/docker.service.d

# Create a file with base config for service
sudo nano /etc/systemd/system/docker.service.d/override.conf
```

``` bash 
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd
```

```bash
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
systemctl daemon-reload
sudo systemctl restart docker
```
## Configure firewall

Script to configure ufw

```bash
#!/bin/bash

# Variables
PUB_IFACE="ens3"                  # Replace by public inteface
ZT_IFACE="ztr2qxgeyd"             # Replace by zerotier interface

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
