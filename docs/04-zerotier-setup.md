# ZeroTier Setup

This guide covers ZeroTier installation and network configuration for secure private networking.

## Create ZeroTier Network

Before installing ZeroTier on your servers, create a private network through the ZeroTier web interface:

### 1. Sign up/Login to ZeroTier Central

- Go to [my.zerotier.com](https://my.zerotier.com)
- Create an account or login to your existing account

### 2. Create a New Network

- Click "Create" or "Create Network"
- Choose "Private Network" (recommended for security)
- Give your network a descriptive name (e.g., "Docker Swarm Management")

### 3. Configure Network Settings

- **Network ID**: Note the 16-character network ID (e.g., `8056c2e21c000001`)
- **Access Control**: Set to "Private" for enhanced security
- **IPv4 Auto-Assign**: Enable and configure your desired subnet (e.g., `10.0.0.0/24`)
- **IPv6 Auto-Assign**: Optional, can be disabled if not needed

### 4. Advanced Settings (Optional)

- **Route Management**: Enable if you want ZeroTier to manage routes
- **Bridge Mode**: Disable unless you need to bridge to physical networks
- **DNS**: Configure custom DNS servers if needed

### 5. Save the Network

- Click "Save" to create your network
- Keep the Network ID handy - you'll need it for joining servers

## Install ZeroTier

Install ZeroTier on your server:

```bash
curl -s https://install.zerotier.com | sudo bash
sudo systemctl enable --now zerotier-one
sudo zerotier-cli join <your-network-id>
```

> **Note**: Replace `<your-network-id>` with the 16-character network ID from step 3 above.

## Authorize the Node

1. Go back to your ZeroTier Central dashboard
2. Find your network and click on it
3. Look for your server in the "Members" section
4. Check the box next to your server to authorize it
5. The server will receive an IP address from your configured subnet

## Verify Connection

Check that ZeroTier is working properly:

```bash
# Check ZeroTier status
sudo zerotier-cli status

# List networks
sudo zerotier-cli listnetworks

# Check interface
ip addr show | grep zt
```

## Test Connectivity

If you have multiple servers, test connectivity between them:

```bash
# From server 1 to server 2
ping <zerotier-ip-of-server-2>

# Test SSH over ZeroTier
ssh user@<zerotier-ip-of-server-2>
```

## Next Steps

Proceed to [GitLab CI Setup](05-gitlab-ci-setup.md) to configure CI/CD pipelines.
