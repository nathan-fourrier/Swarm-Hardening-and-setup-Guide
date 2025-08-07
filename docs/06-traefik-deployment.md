# Traefik Deployment

This guide covers deploying Traefik as a reverse proxy with automatic SSL certificate management.

## Create Traefik Repository

Create a new GitLab project for your Traefik deployment:

1. Create a new project named "traefik" in your GitLab group
2. Clone the project locally
3. Copy the configuration files:

```bash
git clone <your-group>/traefik.git
cd traefik
mkdir -p stacks
```

## Create Traefik Stack File

Create `stacks/traefik_stack.yml`:

```yaml
version: '3.8'

services:
  traefik:
    image: traefik:latest
    ports:
      - "80:80"
      - "443:443"
    networks:
      - traefik-public
    command:
      - --providers.swarm=true
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --entrypoints.web.address=:80
      - --entrypoints.websecure.address=:443
      - --log.level=DEBUG
      - --certificatesresolvers.certbot.acme.tlschallenge=true
      - --certificatesresolvers.certbot.acme.caserver=https://acme-v02.api.letsencrypt.org/directory
      - --certificatesresolvers.certbot.acme.email=postmaster@yourdomain.com
      - --certificatesresolvers.certbot.acme.storage=/letsencrypt/acme-v2.json
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - traefik-certificates:/letsencrypt
    deploy:
      placement:
        constraints:
          - node.role == manager

networks:
  traefik-public:
    external: true

volumes:
  traefik-certificates:
```

## Create GitLab CI Configuration

Create `.gitlab-ci.yml`:

```yaml
include:
  - project: 'your-group/runners'  # Replace with your actual project path
    ref: main
    file: "swarm-deployment.yml"

deploy_traefik:
  extends: .deploy_docker
  variables:
    STACK_FILE: "stacks/traefik_stack.yml"
    STACK_NAME: "traefik"
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
```

## Create Traefik Public Network

Before deploying, create the required network:

```bash
# Create the traefik-public network
docker network create --driver overlay --attachable traefik-public
```

## Deploy Traefik

1. **Push your changes to GitLab:**
   ```bash
   git add .
   git commit -m "Initial Traefik deployment"
   git push origin main
   ```

2. **Trigger the deployment:**
   - Go to your GitLab project → CI/CD → Pipelines
   - Click "Run pipeline" or wait for automatic trigger
   - Monitor the deployment logs

3. **Verify deployment:**
   ```bash
   # Check if the stack is running
   docker stack ls
   
   # Check service status
   docker service ls
   
   # Check service logs
   docker service logs traefik_traefik
   ```

## Configure Your Domain

1. Point your domain to your server's public IP
2. Wait for DNS propagation
3. Test HTTPS access to your domain

## Next Steps

Proceed to [Portainer Deployment](07-portainer-deployment.md) to set up the management UI (optional).
