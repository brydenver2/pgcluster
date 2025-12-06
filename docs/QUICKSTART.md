# Quick Start Guide

This is a quick reference for deploying the PostgreSQL cluster. For detailed instructions, see [DEPLOYMENT.md](DEPLOYMENT.md).

## Prerequisites

- Docker installed
- At least 4GB RAM available
- At least 20GB disk space

## Quick Local Deployment (Easiest)

```bash
# 1. Build images
./build.sh

# 2. Set version
export pg_version=$(cat version.txt)

# 3. Create network
docker network create --driver=bridge pgcluster_network

# 4. Deploy
docker-compose -f docker-compose-test.yml up -d

# 5. Access UI
# Open: http://<your-ip>:8080
```

## Quick Deployment with Portainer

```bash
# 1. Start local registry
docker run -d -p 5000:5000 --restart=always --name registry registry:2

# 2. Build and push images
export DOCKER_REGISTRY=localhost:5000
./build.sh

# 3. Install Portainer (if not installed)
docker volume create portainer_data
docker run -d -p 9000:9000 --name=portainer --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:latest

# 4. Access Portainer UI
# Open: http://<your-ip>:9000

# 5. In Portainer:
#    - Go to Stacks → Add Stack
#    - Upload docker-compose-portainer.yml
#    - Set environment variables:
#      DOCKER_REGISTRY=localhost:5000
#      pg_version=1.0.1
#    - Deploy
```

## Useful Commands

```bash
# Check status
docker-compose -f docker-compose-test.yml ps

# View logs
docker-compose -f docker-compose-test.yml logs -f

# Stop cluster
docker-compose -f docker-compose-test.yml down

# Remove data (WARNING: destroys all data)
docker-compose -f docker-compose-test.yml down -v

# Check replication
docker exec -it <pg01-container> su - postgres -c "repmgr cluster show"

# Connect to database
docker exec -it <pgpool-container> psql -h localhost -p 9999 -U postgres
```

## Registry Commands

```bash
# List images in registry
curl http://localhost:5000/v2/_catalog

# List tags for an image
curl http://localhost:5000/v2/pg/tags/list
```

## Troubleshooting

```bash
# Can't access UI on localhost?
# Use your actual IP instead: http://192.168.1.100:8080

# Containers restarting?
docker logs <container-name>

# Registry connection issues?
# Add to /etc/docker/daemon.json:
{
  "insecure-registries": ["localhost:5000"]
}
# Then: sudo systemctl restart docker
```

## Files Reference

- **DEPLOYMENT.md** - Complete deployment guide with all options
- **README.md** - Architecture and technical details
- **build.sh** - Build all images (with optional registry push)
- **docker-compose-test.yml** - Test deployment (3 nodes)
- **docker-compose-portainer.yml** - Portainer-specific deployment
- **docker-compose.yml** - Production swarm template

## Getting Help

For detailed information:
- Full deployment guide: [DEPLOYMENT.md](DEPLOYMENT.md)
- Architecture details: [README.md](README.md)
- Pgpool watchdog setup: [doc/pgpoolwatchdog.md](doc/pgpoolwatchdog.md)
