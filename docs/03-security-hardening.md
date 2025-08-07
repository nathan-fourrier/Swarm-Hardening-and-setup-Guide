# Security Hardening

This guide covers SSH hardening, TLS certificate setup, and Docker API security.

## SSH Hardening

### Create CI Deploy User

Create a dedicated user for GitLab CI deployments:

```bash
sudo adduser ci-deploy --disabled-password --gecos ""
sudo usermod -aG docker ci-deploy
```

### Setup SSH Key for CI

Generate SSH key pair and configure access:

```bash
# Generate key pair
ssh-keygen -t rsa -b 4096 -C "ci-deploy"

# Setup SSH directory
sudo mkdir -p /home/ci-deploy/.ssh
sudo nano /home/ci-deploy/.ssh/authorized_keys
sudo chown -R ci-deploy:ci-deploy /home/ci-deploy/.ssh
sudo chmod 700 /home/ci-deploy/.ssh
sudo chmod 600 /home/ci-deploy/.ssh/authorized_keys
```

### Configure SSH Tunnel Access

Edit `/home/ci-deploy/.ssh/authorized_keys`:

```
command="echo 'Tunnel only'",no-pty,no-agent-forwarding,no-X11-forwarding,permitopen="127.0.0.1:2376" ssh-rsa AAAA...
```

## Docker TLS Setup

### Create TLS Certificates

```bash
mkdir -p ~/docker-certs && cd ~/docker-certs

# Generate CA
openssl genrsa -aes256 -out ca-key.pem 4096
openssl req -new -x509 -days 365 -key ca-key.pem -sha256 -out ca.pem

# Generate server certificate
openssl genrsa -out server-key.pem 4096
openssl req -subj "/CN=$(hostname)" -new -key server-key.pem -out server.csr

echo subjectAltName = IP:127.0.0.1,IP:<YOUR_PUBLIC_IP> > extfile.cnf
echo extendedKeyUsage = serverAuth >> extfile.cnf

openssl x509 -req -days 365 -sha256 -in server.csr -CA ca.pem -CAkey ca-key.pem \
  -CAcreateserial -out server-cert.pem -extfile extfile.cnf

# Generate client certificate
openssl genrsa -out client-key.pem 4096
openssl req -subj '/CN=client' -new -key client-key.pem -out client.csr

echo extendedKeyUsage = clientAuth > extfile-client.cnf

openssl x509 -req -days 365 -sha256 -in client.csr -CA ca.pem -CAkey ca-key.pem \
  -CAcreateserial -out client-cert.pem -extfile extfile-client.cnf
```

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

Create `/etc/docker/daemon.json`:

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

Restart Docker:

```bash
sudo systemctl daemon-reload
sudo systemctl restart docker
```

## Network Access Control

### Get Network Information

Run the network detection script:

```bash
chmod +x assets/scripts/get_network_info.sh
sudo ./assets/scripts/get_network_info.sh
```

### Configure SSH Access by Network

Create `/etc/ssh/sshd_config.d/ci-deploy.conf`:

```text
Match Address 10.0.0.0/24 # Replace with your ZeroTier CIDR
    AllowUsers *

Match Address *,!10.0.0.0/24 # Replace with your ZeroTier CIDR
    AllowUsers ci-deploy

Match User ci-deploy
    X11Forwarding no
    AllowTcpForwarding yes
    PermitTTY no
    ForceCommand echo "Tunnel only"
```

Restart SSH:

```bash
sudo systemctl restart ssh
```

## Next Steps

Proceed to [ZeroTier Setup](04-zerotier-setup.md) to configure private networking.
