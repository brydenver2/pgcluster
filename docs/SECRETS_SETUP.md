# PostgreSQL Cluster - Docker Secrets Setup

This guide explains how to use Docker secrets to securely manage passwords in your PostgreSQL cluster.

## Overview

The cluster now uses Docker secrets instead of plain environment variables for sensitive data:
- `postgres_password` - Password for the postgres superuser
- `repmgr_password` - Password for replication manager (used by repmgr and pgpool)

## Prerequisites

- Docker Swarm must be initialized
- You must have manager node access

## Setup Instructions

### 1. Initialize Docker Swarm (if not already done)

```bash
docker swarm init --advertise-addr=<your-ip>
```

### 2. Create the Secrets

Use the provided setup script:

```bash
./setup-secrets.sh
```

The script will:
- Check if Docker Swarm is active
- Prompt you to create both required secrets
- Handle existing secrets with option to recreate
- Validate passwords match

**Alternatively, create secrets manually:**

```bash
# Create postgres superuser password
echo -n "your_secure_postgres_password" | docker secret create postgres_password -

# Create replication manager password
echo -n "your_secure_repmgr_password" | docker secret create repmgr_password -
```

### 3. Rebuild Docker Images

After updating the scripts, rebuild the images:

```bash
./build.sh
```

### 4. Deploy the Stack

```bash
docker stack deploy -c docker-compose-portainer.yml pgcluster
```

## How It Works

### Environment Variables

Each service now uses `*_FILE` environment variables that point to the secret files:

- **PostgreSQL nodes (pg01, pg02, pg03)**:
  - `POSTGRES_PASSWORD_FILE=/run/secrets/postgres_password`
  - `REPMGRPWD_FILE=/run/secrets/repmgr_password`

- **Pgpool**:
  - `REPMGRPWD_FILE=/run/secrets/repmgr_password`

- **Manager**:
  - `REPMGRPWD_FILE=/run/secrets/repmgr_password`

### Code Changes

The following files were updated to support reading passwords from files:

1. **postgres/initdb.sh** - Reads `POSTGRES_PASSWORD_FILE` and `REPMGRPWD_FILE`
2. **pgpool/bin/entrypoint.sh** - Reads `REPMGRPWD_FILE`
3. **manager/server/config/config.js** - Reads `REPMGRPWD_FILE`

All scripts maintain backward compatibility with direct environment variables for non-production use.

## Managing Secrets

### View Secrets

```bash
# List all secrets
docker secret ls

# Inspect secret metadata (password content is never shown)
docker secret inspect postgres_password
```

### Update Secrets

Secrets are immutable. To update:

1. Remove the services using the secret:
   ```bash
   docker stack rm pgcluster
   ```

2. Remove the old secret:
   ```bash
   docker secret rm postgres_password
   docker secret rm repmgr_password
   ```

3. Create new secrets:
   ```bash
   ./setup-secrets.sh
   ```

4. Redeploy:
   ```bash
   docker stack deploy -c docker-compose-portainer.yml pgcluster
   ```

### Remove Secrets

```bash
# Remove services first
docker stack rm pgcluster

# Then remove secrets
docker secret rm postgres_password repmgr_password
```

## Security Best Practices

1. **Strong Passwords**: Use strong, unique passwords for production
2. **Secret Rotation**: Regularly rotate secrets in production environments
3. **Access Control**: Limit who can create/view secrets to manager nodes only
4. **Audit Logs**: Monitor secret access and changes
5. **Never Commit**: Never commit secret values to version control

## Troubleshooting

### Secret not found error

```
Error: secret not found
```

**Solution**: Create the secrets before deploying:
```bash
./setup-secrets.sh
```

### Permission denied reading secret

```
Error: cannot read /run/secrets/postgres_password
```

**Solution**: Ensure the service has the secret mounted in docker-compose.yml:
```yaml
services:
  pg01:
    secrets:
      - postgres_password
```

### Password not working

If you're having authentication issues:

1. Verify the secret was created correctly:
   ```bash
   docker secret ls
   ```

2. Check container logs for password loading messages:
   ```bash
   docker service logs pgcluster_pg01
   ```

3. For existing clusters, you may need to manually update passwords:
   ```bash
   docker exec -it <container> psql -U postgres -c "ALTER USER postgres PASSWORD 'newpassword';"
   ```

## Migration from Environment Variables

If you have an existing deployment using environment variables:

1. **Backup your data** before proceeding
2. Note your current passwords from docker-compose.yml
3. Create secrets with those passwords
4. Update docker-compose.yml to use secrets (already done)
5. Rebuild and redeploy

**Note**: For existing databases, passwords won't automatically change. You'll need to either:
- Reinitialize the cluster (data loss), or
- Manually update passwords to match your secrets

## For Development/Testing

For non-production use, you can still use environment variables directly:

```yaml
environment:
  POSTGRES_PASSWORD: testpass123
  REPMGRPWD: rep123
```

The scripts check for `*_FILE` variables first, then fall back to direct environment variables.
