# Portainer Deployment (Optional)

This guide covers deploying Portainer as a management UI for your Docker Swarm cluster.

## Create Portainer Repository

Create a new GitLab project for your Portainer deployment:

1. Create a new project named "portainer" in your GitLab group
2. Clone the project locally:

```bash
git clone <your-group>/portainer.git
cd portainer
mkdir -p stacks
```

## Create Portainer Stack File

Create `stacks/portainer_stack.yml`:

```yaml
version: '3.8'

services:
  portainer:
    image: portainer/portainer-ce:latest
    command: -H unix:///var/run/docker.sock
    ports:
      - 9000:9000
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
    networks:
      - portainer

volumes:
  portainer_data:

networks:
  portainer:
    driver: overlay
```

## Create GitLab CI Configuration

Create `.gitlab-ci.yml`:

```yaml
include:
  - project: 'your-group/runners'  # Replace with your actual project path
    ref: main
    file: "swarm-deployment.yml"

variables:
  STACK_FILE: "stacks/portainer_stack.yml"
  STACK_NAME: "portainer"

deploy_portainer:
  extends: .deploy_docker
  variables:
    STACK_FILE: "stacks/portainer_stack.yml"
    STACK_NAME: "portainer"
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
  environment:
    name: production
    url: http://your-server-ip:9000
```

## Deploy Portainer

1. **Push your changes to GitLab:**
   ```bash
   git add .
   git commit -m "Initial Portainer deployment"
   git push origin main
   ```

2. **Trigger the deployment:**
   - Go to your GitLab project → CI/CD → Pipelines
   - Click "Run pipeline" or wait for automatic trigger
   - Monitor the deployment logs

3. **Access Portainer:**
   - Navigate to `http://your-server-ip:9000`
   - Complete the initial setup wizard

## Initial Portainer Setup

1. **Create Admin User:**
   - You'll be prompted to create an admin user
   - Choose a strong password for security

2. **Connect to Docker Swarm:**
   - In Portainer, go to "Environments" → "Add Environment"
   - Select "Docker Swarm" as the environment type
   - Use the following settings:
     - **Name**: Docker Swarm
     - **Environment URL**: `tcp://tasks.agent:9001`
     - **TLS**: Disabled (since we're using `--tlsskipverify`)

## Integration with Traefik (Optional)

If you want to access Portainer through Traefik instead of direct port access, update the stack file:

```yaml
# In stacks/portainer_stack.yml, add these labels:
labels:
  - portainer.agent=true
  - traefik.enable=true
  - traefik.http.routers.portainer.rule=Host(`portainer.yourdomain.com`)
  - traefik.http.routers.portainer.entrypoints=websecure
  - traefik.http.routers.portainer.tls=true
  - traefik.http.routers.portainer.tls.certresolver=letsencrypt
  - traefik.http.services.portainer.loadbalancer.server.port=9000
```

Then access Portainer at `https://portainer.yourdomain.com` instead of `http://your-server-ip:9000`.

## Next Steps

Proceed to [Secrets Management](08-secrets-management.md) to learn about secure credential handling.
