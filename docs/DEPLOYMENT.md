# PostgreSQL Cluster Deployment Guide

This guide provides step-by-step instructions for deploying the PostgreSQL cluster using Docker CLI, Docker Compose, Docker Swarm, or Portainer.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Building the Images](#building-the-images)
- [Deployment Options](#deployment-options)
  - [Option 1: Local Docker Compose](#option-1-local-docker-compose)
  - [Option 2: Docker Swarm](#option-2-docker-swarm)
  - [Option 3: Portainer Deployment](#option-3-portainer-deployment)
- [Using a Local Registry](#using-a-local-registry)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

Before deploying, ensure you have:

- Docker Engine installed (20.10.0 or later)
- Docker Compose installed (v3.2 or later)
- At least 4GB of available RAM
- At least 20GB of available disk space
- Network connectivity between nodes (if deploying in multi-node setup)

---

## Building the Images

### Building Locally

To build all images locally without pushing to a registry:

```bash
# Build all images (postgres, pgpool, manager)
./build.sh
```

This will create three images tagged with the version from `version.txt`:
- `pg:<version>` - PostgreSQL with replication support
- `pgpool:<version>` - Pgpool-II connection pooler
- `manager:<version>` - Web-based management interface

### Building and Pushing to a Registry

If you want to push images to a local or remote registry:

```bash
# Set your registry address
export DOCKER_REGISTRY=192.168.1.100:5000

# Build and push
./build.sh
```

The build script will automatically tag and push images to the specified registry if `DOCKER_REGISTRY` is set.

---

## Deployment Options

### Option 1: Local Docker Compose

This is the simplest deployment for testing on a single machine.

#### Step 1: Set Environment Variables

```bash
export pg_version=$(cat version.txt)
```

#### Step 2: Create Network

```bash
docker network create --driver=bridge pgcluster_network
```

#### Step 3: Deploy the Stack

For a 3-node test cluster:

```bash
docker-compose -f docker-compose-test.yml up -d
```

Or for a simpler 2-node setup:

```bash
docker-compose -f docker-compose.yml up -d
```

#### Step 4: Verify Services

```bash
# Check running containers
docker ps

# Check logs
docker-compose -f docker-compose-test.yml logs -f
```

#### Step 5: Access the Management Interface

Open your browser and navigate to:
```
http://<your-host-ip>:8080
```

**Note:** Use your machine's IP address, not `localhost` or `127.0.0.1`, as the interface may not work properly with localhost.

#### Stopping the Cluster

```bash
docker-compose -f docker-compose-test.yml down

# To also remove volumes (WARNING: destroys all data)
docker-compose -f docker-compose-test.yml down -v
```

---

### Option 2: Docker Swarm

For production deployments across multiple nodes with high availability.

#### Step 1: Initialize Swarm

On the manager node:

```bash
# Initialize swarm
docker swarm init --advertise-addr=<manager-ip>

# Get join token for workers
docker swarm join-token worker
```

On worker nodes, run the join command provided.

#### Step 2: Set Environment Variables

```bash
export pg_version=$(cat version.txt)
```

#### Step 3: Create Overlay Network

```bash
docker network create --driver=overlay --attachable=true pgcluster_network
```

#### Step 4: Deploy the Stack

For a test deployment on a single-node swarm:

```bash
docker stack deploy -c docker-compose-test.yml pgcluster
```

#### Step 5: Monitor Deployment

```bash
# Check services
docker stack services pgcluster

# Check service logs
docker service logs pgcluster_pg01
docker service logs pgcluster_pgpool
docker service logs pgcluster_manager
```

#### Step 6: Access the Management Interface

Navigate to:
```
http://<swarm-manager-ip>:8080
```

#### Removing the Stack

```bash
# Remove the stack
docker stack rm pgcluster

# Remove volumes (if needed)
docker volume ls | grep pgcluster | awk '{print $2}' | xargs docker volume rm
```

---

### Option 3: Portainer Deployment

Portainer provides a web-based UI for managing Docker containers and stacks.

#### Prerequisites

1. **Install Portainer** (if not already installed):

```bash
docker volume create portainer_data

docker run -d -p 9000:9000 -p 9443:9443 \
  --name=portainer --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:latest
```

Access Portainer at: `http://<your-host-ip>:9000`

2. **Build and Push Images to Registry**:

Portainer needs to pull images from a registry. Set up a local registry first:

```bash
# Start a local registry
docker run -d -p 5000:5000 --restart=always --name registry registry:2

# Set registry environment variable
export DOCKER_REGISTRY=localhost:5000

# Build and push images
./build.sh
```

Or configure Docker to use your existing registry server:

```bash
export DOCKER_REGISTRY=192.168.1.100:5000
./build.sh
```

#### Deploying via Portainer Web UI

1. **Login to Portainer** at `http://<your-host-ip>:9000`

2. **Select your environment** (local Docker or Swarm)

3. **Navigate to Stacks** → **Add Stack**

4. **Configure the Stack**:
   - Name: `pgcluster`
   - Build method: Upload or Web editor

5. **Paste the Stack Configuration**:

   If you uploaded images to `localhost:5000`, use this docker-compose configuration:

   ```yaml
   version: '3.2'
   services:
     pg01:
       image: localhost:5000/pg:1.0.1
       environment:
         INITIAL_NODE_TYPE: master
         NODE_ID: 1
         NODE_NAME: pg01
         MSLIST: "myservice"
         MSOWNERPWDLIST: "myservice_owner"
         MSUSERPWDLIST: "myservice_user"
         REPMGRPWD: rep123
         REPMGRD_FAILOVER_MODE: manual
         PGMASTER: pg01
       ports:
         - 15432:5432
       volumes:
         - pg01db:/data
         - pg01arc:/archive
       networks:
         - pgcluster_network

     pg02:
       image: localhost:5000/pg:1.0.1
       environment:
         INITIAL_NODE_TYPE: slave
         NODE_ID: 2
         NODE_NAME: pg02
         MSLIST: "myservice"
         MSOWNERPWDLIST: "myservice_owner"
         MSUSERPWDLIST: "myservice_user"
         REPMGRPWD: rep123
         REPMGRD_FAILOVER_MODE: manual
         PGMASTER: pg01
       ports:
         - 25432:5432
       volumes:
         - pg02db:/data
         - pg02arc:/archive
       networks:
         - pgcluster_network
       depends_on:
         - pg01

     pg03:
       image: localhost:5000/pg:1.0.1
       environment:
         INITIAL_NODE_TYPE: slave
         NODE_ID: 3
         NODE_NAME: pg03
         MSLIST: "myservice"
         MSOWNERPWDLIST: "myservice_owner"
         MSUSERPWDLIST: "myservice_user"
         REPMGRPWD: rep123
         REPMGRD_FAILOVER_MODE: manual
         PGMASTER: pg01
       ports:
         - 35432:5432
       volumes:
         - pg03db:/data
         - pg03arc:/archive
       networks:
         - pgcluster_network
       depends_on:
         - pg01

     pgpool:
       image: localhost:5000/pgpool:1.0.1
       ports:
         - 9999:9999
       environment:
         PGMASTER_NODE_NAME: pg01
         PG_BACKEND_NODE_LIST: 0:pg01:5432:1:/data:ALLOW_TO_FAILOVER,1:pg02:5432:1:/data:ALLOW_TO_FAILOVER,2:pg03:5432:1:/data:ALLOW_TO_FAILOVER
         PGP_NODE_NAME: pgpool
         REPMGRPWD: rep123
         FAILOVER_MODE: automatic
         PGPOOL_HEALTH_CHECK_MAX_RETRIES: 3
         PGPOOL_HEALTH_CHECK_RETRY_DELAY: 1
         PGPOOL_FAIL_OVER_ON_BACKEND_ERROR: "off"
         PGPOOL_HEALTH_CHECK_PERIOD: 5
         PGPOOL_NUM_INIT_CHILDREN: 50
         PGPOOL_LOAD_BALANCE_MODE: "no"
         PGPOOL_LOG_CONNECTIONS: "off"
       networks:
         - pgcluster_network
       depends_on:
         - pg01
         - pg02
         - pg03

     manager:
       image: localhost:5000/manager:1.0.1
       ports:
         - 8080:8080
       environment:
         PG_BACKEND_NODE_LIST: 0:pg01:5432:1:/data:ALLOW_TO_FAILOVER,1:pg02:5432:1:/data:ALLOW_TO_FAILOVER,2:pg03:5432:1:/data:ALLOW_TO_FAILOVER
         REPMGRPWD: rep123
         DBHOST: pgpool
       networks:
         - pgcluster_network
       volumes:
         - /var/run/docker.sock:/var/run/docker.sock

   volumes:
     pg01db:
     pg02db:
     pg03db:
     pg01arc:
     pg02arc:
     pg03arc:

   networks:
     pgcluster_network:
       driver: bridge
   ```

   **Note:** Replace `1.0.1` with your actual version from `version.txt` and update the registry URL if different.

6. **Add Environment Variables** (in Portainer):
   - No additional environment variables needed if using the config above

7. **Deploy the Stack**
   - Click "Deploy the stack"
   - Wait for all services to start (check the Containers list)

8. **Access Management Interface**:
   Navigate to `http://<your-host-ip>:8080`

#### Deploying via Portainer CLI (API)

You can also deploy using Portainer's API:

```bash
# Set Portainer details
PORTAINER_URL="http://localhost:9000"
PORTAINER_USERNAME="admin"
PORTAINER_PASSWORD="your-password"
PORTAINER_ENDPOINT_ID=1  # Usually 1 for local endpoint

# Login and get token
TOKEN=$(curl -s -X POST "${PORTAINER_URL}/api/auth" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"${PORTAINER_USERNAME}\",\"password\":\"${PORTAINER_PASSWORD}\"}" | \
  jq -r '.jwt')

# Deploy stack from docker-compose file
curl -X POST "${PORTAINER_URL}/api/stacks" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: multipart/form-data" \
  -F "Name=pgcluster" \
  -F "EndpointId=${PORTAINER_ENDPOINT_ID}" \
  -F "file=@docker-compose-test.yml" \
  -F "Env=[{\"name\":\"pg_version\",\"value\":\"$(cat version.txt)\"}]"
```

**Note:** You'll need `jq` installed for the above command to work. Install it with:
- Debian/Ubuntu: `sudo apt install jq`
- RHEL/CentOS/Fedora: `sudo dnf install jq` (or `sudo yum install jq` on older versions)
- macOS: `brew install jq`

---

## Using a Local Registry

A local registry is useful for:
- Deploying to multiple nodes in a swarm
- Using Portainer
- Keeping images centralized

### Setting Up a Local Registry

#### Quick Start

```bash
# Start registry on default port 5000
docker run -d -p 5000:5000 --restart=always --name registry registry:2
```

#### With Persistent Storage

```bash
# Create volume for registry data
docker volume create registry_data

# Start registry with volume
docker run -d -p 5000:5000 --restart=always --name registry \
  -v registry_data:/var/lib/registry \
  registry:2
```

#### Configure Docker to Use Insecure Registry (if using HTTP)

Edit `/etc/docker/daemon.json`:

```json
{
  "insecure-registries": ["localhost:5000", "192.168.1.100:5000"]
}
```

Replace `192.168.1.100:5000` with your registry's IP and port.

Restart Docker:

```bash
sudo systemctl restart docker
```

### Build and Push to Registry

```bash
# Set registry
export DOCKER_REGISTRY=localhost:5000

# Or use remote registry
# export DOCKER_REGISTRY=192.168.1.100:5000

# Build and push
./build.sh
```

### Verify Images in Registry

```bash
# List repositories
curl http://localhost:5000/v2/_catalog

# List tags for an image
curl http://localhost:5000/v2/pg/tags/list
curl http://localhost:5000/v2/pgpool/tags/list
curl http://localhost:5000/v2/manager/tags/list
```

### Updating docker-compose Files for Registry

If your images are in a registry, update the image references in your docker-compose files:

```yaml
services:
  pg01:
    image: localhost:5000/pg:${pg_version}
    # ... rest of config
```

---

## Verification

After deployment, verify your cluster is healthy:

### Check Container Status

```bash
# Docker Compose
docker-compose -f docker-compose-test.yml ps

# Docker Swarm
docker stack services pgcluster
```

### Check Database Connectivity

```bash
# Connect to pgpool
docker exec -it <pgpool-container-id> psql -h localhost -p 9999 -U postgres

# Or connect directly to postgres
docker exec -it <pg01-container-id> psql -h localhost -p 5432 -U postgres
```

### Check Replication Status

```bash
# Inside postgres container
docker exec -it <pg01-container-id> su - postgres -c "psql -c 'SELECT * FROM pg_stat_replication;'"
```

### Check Repmgr Cluster Status

```bash
docker exec -it <pg01-container-id> su - postgres -c "repmgr cluster show"
```

### Access Management UI

Navigate to `http://<host-ip>:8080` and verify:
- All nodes show as green/healthy
- Connection pool is active
- Replication is working

---

## Troubleshooting

### Issue: Containers Keep Restarting

**Solution:**
```bash
# Check logs
docker logs <container-name>

# Common issues:
# 1. Port already in use - change port mappings
# 2. Insufficient memory - increase Docker memory limit
# 3. Volume permission issues - check volume permissions
```

### Issue: Cannot Access Management UI

**Solution:**
```bash
# Don't use localhost, use actual IP
ip addr show

# Access via: http://<actual-ip>:8080
# Not: http://localhost:8080
```

### Issue: Registry Connection Refused

**Solution:**
```bash
# Ensure registry is running
docker ps | grep registry

# Check insecure-registries in /etc/docker/daemon.json
cat /etc/docker/daemon.json

# Restart Docker after config changes
sudo systemctl restart docker
```

### Issue: Replication Not Working

**Solution:**
```bash
# Check if master is accessible from slaves
docker exec -it <pg02-container> ping pg01

# Check repmgr status
docker exec -it <pg01-container> su - postgres -c "repmgr cluster show"

# Check postgres logs
docker logs <pg01-container>
docker logs <pg02-container>
```

### Issue: Pgpool Shows Backend Down

**Solution:**
```bash
# Check pgpool logs
docker logs <pgpool-container>

# Verify backend connectivity
docker exec -it <pgpool-container> psql -h pg01 -p 5432 -U repmgr -d repmgr

# Reset pgpool status
docker exec -it <pgpool-container> rm -f /tmp/pgpool_status
docker restart <pgpool-container>
```

### Issue: Volumes Already Exist

**Solution:**
```bash
# List volumes
docker volume ls | grep pgcluster

# Remove volumes (WARNING: destroys data)
docker volume rm pgcluster_pg01db pgcluster_pg02db pgcluster_pg03db

# Or remove all pgcluster volumes
./delvol.sh
```

### Getting Help

For more detailed information:
- Check main README.md for architecture details
- Review docker-compose files for configuration options
- Check logs: `docker logs <container-name>`
- Exec into containers: `docker exec -it <container-name> /bin/bash`

---

## Security Considerations

For production deployments:

1. **Change Default Passwords**: Update passwords in environment variables
2. **Use SSL/TLS**: Configure PostgreSQL and Pgpool for encrypted connections
3. **Secure Registry**: Use HTTPS and authentication for your registry
4. **Network Isolation**: Use proper network segmentation
5. **Regular Updates**: Keep images updated with security patches

---

## Additional Resources

- Main README: [README.md](README.md)
- Pgpool Watchdog Setup: [doc/pgpoolwatchdog.md](doc/pgpoolwatchdog.md)
- Repmgr Failover: [doc/repmgr_auto.md](doc/repmgr_auto.md)
- Ansible Deployment: [ansible/README.md](ansible/README.md)
