# Docker Swarm Setup

This guide covers Docker installation and Swarm initialization.

## Install Docker Engine

Install Docker using the official installation script:

```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
sudo apt install docker-compose-plugin -y
sudo usermod -aG docker $USER
```

## Initialize Docker Swarm

Initialize the Swarm on the manager node:

```bash
docker swarm init
```

Save the join token for worker nodes:

```bash
# Get the worker join token
docker swarm join-token worker
```

## Verify Swarm Status

Check that Swarm is properly initialized:

```bash
# Check Swarm status
docker info | grep Swarm

# List nodes
docker node ls

# Check Swarm services
docker service ls
```

## Multi-Node Setup (Optional)

### Add Worker Nodes

On each worker node, run the join command provided by the manager:

```bash
docker swarm join --token <worker-token> <manager-ip>:2377
```

### Verify Cluster

On the manager node, verify all nodes are connected:

```bash
docker node ls
```

## Next Steps

Proceed to [Security Hardening](03-security-hardening.md) to configure TLS and SSH security.
