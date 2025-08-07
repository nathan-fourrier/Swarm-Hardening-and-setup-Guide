# Secrets Management

This guide covers Docker Swarm secrets management for secure credential handling.

## Creating Secrets

### Method 1: Create from File

```bash
# Create a secret from a file
echo "my-super-secret-password" | docker secret create db_password -

# Create a secret from an existing file
docker secret create api_key /path/to/api_key.txt

# Create a secret with a specific name
echo "jwt-secret-key" | docker secret create jwt_secret -
```

### Method 2: Create from STDIN

```bash
# Create secret from command output
openssl rand -base64 32 | docker secret create encryption_key -

# Create secret from environment variable
echo $MYSQL_ROOT_PASSWORD | docker secret create mysql_root_password -
```

## Using Secrets in Docker Compose

Update your `docker-compose.yml` to use secrets:

```yaml
version: '3.8'

services:
  app:
    image: my-app:latest
    networks:
      - traefik-public
    deploy:
      mode: replicated
      replicas: 2
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.my-app.rule=Host(`my-app.example.com`)"
        - "traefik.http.routers.my-app.entrypoints=websecure"
        - "traefik.http.routers.my-app.tls=true"
        - "traefik.http.routers.my-app.tls.certresolver=letsencrypt"
        - "traefik.http.services.my-app.loadbalancer.server.port=80"
    secrets:
      - db_password
      - api_key
      - jwt_secret
    environment:
      # Reference secrets in environment variables
      - DB_PASSWORD_FILE=/run/secrets/db_password
      - API_KEY_FILE=/run/secrets/api_key
      - JWT_SECRET_FILE=/run/secrets/jwt_secret
      # Regular environment variables (non-sensitive)
      - NODE_ENV=production
      - PORT=80

networks:
  traefik-public:
    external: true

secrets:
  db_password:
    external: true
  api_key:
    external: true
  jwt_secret:
    external: true
```

## Managing Secrets with GitLab CI

### Step 1: Create Secrets in GitLab CI

Add these variables to your GitLab project's CI/CD settings:

| Variable | Description | Type | Protected | Masked |
|----------|-------------|------|-----------|--------|
| `DB_PASSWORD` | Database password | Variable | Yes | Yes |
| `API_KEY` | External API key | Variable | Yes | Yes |
| `JWT_SECRET` | JWT signing secret | Variable | Yes | Yes |

### Step 2: Update GitLab CI Configuration

Update your `.gitlab-ci.yml` to create secrets during deployment:

```yaml
include:
  - project: 'your-group/runners'
    ref: main
    file: "swarm-deployment.yml"

variables:
  STACK_FILE: "docker-compose.yml"
  STACK_NAME: "myapp"

deploy_app:
  extends: .deploy_docker
  variables:
    STACK_FILE: "docker-compose.yml"
    STACK_NAME: "myapp"
  before_script:
    # Create secrets if they don't exist
    - |
      echo "Creating Docker secrets..."
      echo "$DB_PASSWORD" | docker secret create db_password - 2>/dev/null || echo "Secret db_password already exists"
      echo "$API_KEY" | docker secret create api_key - 2>/dev/null || echo "Secret api_key already exists"
      echo "$JWT_SECRET" | docker secret create jwt_secret - 2>/dev/null || echo "Secret jwt_secret already exists"
```

## Application Code Changes

### Node.js Example

```javascript
const fs = require('fs');

// Read secrets from files
const dbPassword = fs.readFileSync('/run/secrets/db_password', 'utf8').trim();
const apiKey = fs.readFileSync('/run/secrets/api_key', 'utf8').trim();
const jwtSecret = fs.readFileSync('/run/secrets/jwt_secret', 'utf8').trim();

// Use secrets in your application
const config = {
  database: {
    password: dbPassword,
    // ... other config
  },
  api: {
    key: apiKey,
    // ... other config
  },
  jwt: {
    secret: jwtSecret,
    // ... other config
  }
};
```

### Python Example

```python
import os

def read_secret(secret_name):
    """Read a secret from Docker secrets"""
    try:
        with open(f'/run/secrets/{secret_name}', 'r') as secret_file:
            return secret_file.read().strip()
    except FileNotFoundError:
        # Fallback to environment variable for development
        return os.environ.get(secret_name.upper())

# Read secrets
db_password = read_secret('db_password')
api_key = read_secret('api_key')
jwt_secret = read_secret('jwt_secret')

# Use in your application
config = {
    'database': {
        'password': db_password,
        # ... other config
    },
    'api': {
        'key': api_key,
        # ... other config
    },
    'jwt': {
        'secret': jwt_secret,
        # ... other config
    }
}
```

## Secret Management Commands

### List All Secrets

```bash
docker secret ls
```

### Inspect a Secret

```bash
docker secret inspect secret_name
```

### Remove a Secret

```bash
docker secret rm secret_name
```

### Update a Secret

```bash
# Remove old secret
docker secret rm old_secret_name

# Create new secret
echo "new-secret-value" | docker secret create new_secret_name -

# Redeploy the stack to use the new secret
docker stack deploy -c docker-compose.yml stack_name
```

## Best Practices

1. **Never commit secrets to Git:**
   - Use `.gitignore` to exclude secret files
   - Store secrets in GitLab CI/CD variables
   - Use external secret management for production

2. **Secret naming conventions:**
   ```bash
   # Use descriptive names
   docker secret create app_db_password -
   docker secret create app_api_key -
   docker secret create app_jwt_secret -
   ```

3. **Access control:**
   - Only grant secrets to services that need them
   - Use different secrets for different environments
   - Rotate secrets regularly

## Next Steps

Proceed to [Troubleshooting](09-troubleshooting.md) for common issues and solutions.
