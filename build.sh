#!/bin/bash

# Docker Registry Configuration
# Set DOCKER_REGISTRY to push images to a registry (required for Portainer and multi-node deployments)
# Examples:
#   export DOCKER_REGISTRY=localhost:5000        # Local registry
#   export DOCKER_REGISTRY=192.168.1.100:5000    # Remote registry
#   export DOCKER_REGISTRY=myregistry.com:5000   # Custom registry
#
# If DOCKER_REGISTRY is not set, images will only be built locally

# Check if DOCKER_REGISTRY is set via environment variable, otherwise use default
if [ -z "$DOCKER_REGISTRY" ]; then
  # Uncomment and set the line below to use a default registry
  # DOCKER_REGISTRY=localhost:5000
  echo "INFO: DOCKER_REGISTRY not set. Images will be built locally only."
  echo "INFO: To push to a registry, set DOCKER_REGISTRY environment variable:"
  echo "      export DOCKER_REGISTRY=localhost:5000"
  echo ""
fi

VER=`cat version.txt`
echo "Building images with version: ${VER}"
if [ ! -z "$DOCKER_REGISTRY" ]; then
  echo "Registry: ${DOCKER_REGISTRY}"
fi
echo ""

# Optional: Remove existing pgcluster volumes to start fresh
# Uncomment the following line if you want to clean volumes before building
# docker volume ls | grep pgcluster | awk '{print $2}' | xargs docker volume rm 2>/dev/null

echo "==> Building PostgreSQL image..."
docker build -t pg:${VER} --no-cache=false -f postgres/Dockerfile ./postgres
if [ $? -ne 0 ]; then
  echo "ERROR: Failed to build pg:${VER}"
  exit 1
fi
echo "✓ Successfully built pg:${VER}"

if [ ! -z "$DOCKER_REGISTRY" ]; then
  echo "==> Pushing pg:${VER} to registry ${DOCKER_REGISTRY}..."
  docker tag pg:${VER} ${DOCKER_REGISTRY}/pg:${VER}
  docker push ${DOCKER_REGISTRY}/pg:${VER}
  if [ $? -eq 0 ]; then
    echo "✓ Successfully pushed ${DOCKER_REGISTRY}/pg:${VER}"
  else
    echo "ERROR: Failed to push to registry"
    exit 1
  fi
fi

echo ""
echo "==> Building Pgpool image..."
docker build -t pgpool:${VER} -f pgpool/Dockerfile ./pgpool
if [ $? -ne 0 ]; then
  echo "ERROR: Failed to build pgpool:${VER}"
  exit 1
fi
echo "✓ Successfully built pgpool:${VER}"

if [ ! -z "$DOCKER_REGISTRY" ]; then
  echo "==> Pushing pgpool:${VER} to registry ${DOCKER_REGISTRY}..."
  docker tag pgpool:${VER} ${DOCKER_REGISTRY}/pgpool:${VER}
  docker push ${DOCKER_REGISTRY}/pgpool:${VER}
  if [ $? -eq 0 ]; then
    echo "✓ Successfully pushed ${DOCKER_REGISTRY}/pgpool:${VER}"
  else
    echo "ERROR: Failed to push to registry"
    exit 1
  fi
fi

echo ""
echo "==> Building Manager image..."
thisdir=$(pwd)
cd manager/build

# Pass DOCKER_REGISTRY to manager build script
export DOCKER_REGISTRY
./build.bash

if [ $? -ne 0 ]; then
  echo "ERROR: Failed to build manager image"
  cd $thisdir
  exit 1
fi
cd $thisdir
echo "✓ Successfully built manager:${VER}"

echo ""
echo "=== Build Summary ==="
echo "Version: ${VER}"
echo "Images built:"
echo "  - pg:${VER}"
echo "  - pgpool:${VER}"
echo "  - manager:${VER}"

if [ ! -z "$DOCKER_REGISTRY" ]; then
  echo ""
  echo "Images pushed to registry: ${DOCKER_REGISTRY}"
  echo ""
  echo "To verify images in registry:"
  echo "  curl http://${DOCKER_REGISTRY}/v2/_catalog"
else
  echo ""
  echo "Images built locally. To push to a registry:"
  echo "  export DOCKER_REGISTRY=localhost:5000"
  echo "  ./build.sh"
fi

echo ""
echo "=== Next Steps ==="
echo "See DEPLOYMENT.md for deployment instructions"
echo ""
