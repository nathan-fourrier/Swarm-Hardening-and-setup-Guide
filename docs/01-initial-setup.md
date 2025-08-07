# Initial Server Setup

This guide covers the basic server preparation and hardening steps before setting up Docker Swarm.

## Prerequisites

- Ubuntu 20.04+ server with public IP
- Root or sudo access
- Basic Linux administration knowledge

## System Updates

First, ensure your system is up to date:

```bash
sudo apt update && sudo apt upgrade -y
```

## Install Required Packages

Install essential packages for the setup:

```bash
sudo apt install -y curl gnupg2 ca-certificates lsb-release ufw fail2ban
```

## Basic Security Hardening

### 1. Configure UFW Firewall

Run the improved firewall setup script:

```bash
chmod +x assets/scripts/setup_fw.sh
sudo ./assets/scripts/setup_fw.sh
```

### 2. Install and Configure Fail2ban

```bash
sudo systemctl enable fail2ban
sudo systemctl start fail2ban
```

### 3. Secure SSH Configuration

Edit `/etc/ssh/sshd_config`:

```bash
sudo nano /etc/ssh/sshd_config
```

Add these security settings:

```text
# Security settings
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
X11Forwarding no
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
```

Restart SSH service:

```bash
sudo systemctl restart ssh
```

## Verify Setup

Check that all services are running:

```bash
# Check UFW status
sudo ufw status

# Check Fail2ban status
sudo fail2ban-client status

# Check SSH configuration
sudo sshd -t
```

## Next Steps

Once the initial setup is complete, proceed to [Docker Swarm Setup](02-docker-swarm-setup.md).
