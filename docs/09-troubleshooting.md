# Troubleshooting

This guide covers common issues and their solutions.

## Docker Swarm Issues

### Service Not Starting

**Problem:** Service fails to start or stays in "pending" state.

**Solutions:**
```bash
# Check service status
docker service ls

# Check service logs
docker service logs <service-name>

# Check node resources
docker node ls
docker node inspect <node-id>

# Check if there are enough resources
docker system df
```

### Network Connectivity Issues

**Problem:** Services can't communicate with each other.

**Solutions:**
```bash
# Check network status
docker network ls

# Inspect network
docker network inspect <network-name>

# Check if services are on the same network
docker service inspect <service-name> --format '{{.Spec.TaskTemplate.Networks}}'
```

## Traefik Issues

### SSL Certificate Problems

**Problem:** SSL certificates not being issued or renewed.

**Solutions:**
```bash
# Check Traefik logs
docker service logs traefik_traefik

# Verify domain points to server
nslookup yourdomain.com

# Check Let's Encrypt rate limits
# Wait if you've hit rate limits

# Test certificate manually
openssl s_client -connect yourdomain.com:443 -servername yourdomain.com
```

### Service Not Accessible

**Problem:** Service deployed but not accessible through Traefik.

**Solutions:**
```bash
# Check if service has correct labels
docker service inspect <service-name> --format '{{.Spec.TaskTemplate.ContainerSpec.Labels}}'

# Verify Traefik is running
docker service ls | grep traefik

# Check if service is on traefik-public network
docker service inspect <service-name> --format '{{.Spec.TaskTemplate.Networks}}'
```

## ZeroTier Issues

### Connection Problems

**Problem:** ZeroTier interface not connecting or no IP assigned.

**Solutions:**
```bash
# Check ZeroTier status
sudo zerotier-cli status

# List networks
sudo zerotier-cli listnetworks

# Check if node is authorized in ZeroTier Central
# Go to my.zerotier.com and authorize the node

# Restart ZeroTier
sudo systemctl restart zerotier-one
```

### Network Interface Issues

**Problem:** ZeroTier interface not detected by scripts.

**Solutions:**
```bash
# Check interface name
ip link show | grep zt

# Update firewall script with correct interface name
# Edit assets/scripts/setup_fw.sh and update ZT_IFACE variable
```

## GitLab CI Issues

### SSH Connection Failed

**Problem:** CI pipeline fails with SSH connection errors.

**Solutions:**
```bash
# Test SSH connection manually
ssh -i /path/to/private/key ci-deploy@your-server-ip

# Check SSH key format in GitLab variables
# Ensure key is in correct format (no extra spaces/newlines)

# Verify known_hosts content
ssh-keyscan -H your-server-ip
```

### Docker TLS Connection Failed

**Problem:** CI can't connect to Docker daemon via TLS.

**Solutions:**
```bash
# Test TLS connection manually
docker --tlsverify \
  --tlscacert=ca.pem \
  --tlscert=client-cert.pem \
  --tlskey=client-key.pem \
  -H tcp://your-server-ip:2376 \
  version

# Check certificate files
ls -la /etc/docker/certs/

# Verify certificate permissions
sudo chmod 644 /etc/docker/certs/ca.pem
sudo chmod 644 /etc/docker/certs/server-cert.pem
sudo chmod 600 /etc/docker/certs/server-key.pem
```

## Portainer Issues

### Cannot Access Portainer

**Problem:** Portainer web interface not accessible.

**Solutions:**
```bash
# Check if service is running
docker service ls | grep portainer

# Check service logs
docker service logs portainer_portainer

# Check if port is listening
netstat -tlnp | grep 9000

# Verify firewall allows port 9000
sudo ufw status
```

### Cannot Connect to Docker Swarm

**Problem:** Portainer can't connect to Docker Swarm.

**Solutions:**
```bash
# Verify Docker Swarm is initialized
docker info | grep Swarm

# Check if you're on a manager node
docker node ls

# Verify the agent service is running
docker service ls | grep agent
```

## Firewall Issues

### UFW Configuration Problems

**Problem:** Firewall blocking legitimate traffic.

**Solutions:**
```bash
# Check UFW status
sudo ufw status verbose

# Check UFW rules
sudo ufw status numbered

# Temporarily disable UFW for testing
sudo ufw disable

# Re-enable with correct configuration
sudo ./assets/scripts/setup_fw.sh
```

## Common Commands

### System Information
```bash
# Check system resources
htop
df -h
free -h

# Check Docker resources
docker system df
docker stats

# Check service status
docker service ls
docker stack ls
```

### Logs and Debugging
```bash
# View service logs
docker service logs <service-name>

# Follow logs in real-time
docker service logs -f <service-name>

# Check container logs
docker logs <container-id>

# Check system logs
sudo journalctl -u docker
sudo journalctl -u ssh
```

### Network Troubleshooting
```bash
# Check network connectivity
ping <target-ip>
telnet <target-ip> <port>

# Check DNS resolution
nslookup <domain>
dig <domain>

# Check routing
traceroute <target-ip>
```

## Getting Help

If you're still experiencing issues:

1. **Check the logs** - Most issues can be diagnosed from logs
2. **Verify configuration** - Ensure all configuration files are correct
3. **Test connectivity** - Verify network and service connectivity
4. **Check resources** - Ensure sufficient CPU, memory, and disk space
5. **Review security** - Check firewall and access control settings

## Emergency Procedures

### Reset Docker Swarm
```bash
# Leave swarm (on all nodes)
docker swarm leave --force

# Reinitialize swarm (on manager)
docker swarm init
```

### Reset Firewall
```bash
# Reset UFW to default
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw enable
```

### Backup and Restore
```bash
# Backup Docker volumes
docker run --rm -v <volume-name>:/data -v $(pwd):/backup alpine tar czf /backup/<volume-name>.tar.gz -C /data .

# Restore Docker volumes
docker run --rm -v <volume-name>:/data -v $(pwd):/backup alpine tar xzf /backup/<volume-name>.tar.gz -C /data
```
