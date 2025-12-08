#!/usr/bin/env bash
set -euo pipefail

# Allow passing registry via CLI: ./build.sh -r myregistry:5000
DOCKER_REGISTRY="${DOCKER_REGISTRY:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--registry)
      if [[ -z "${2:-}" ]]; then
        echo "ERROR: --registry requires a value"
        exit 1
      fi
      DOCKER_REGISTRY="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [-r|--registry <host:port>]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: $0 [-r|--registry <host:port>]"
      exit 1
      ;;
  esac
done

# If there's a .env file, load it (useful for CI/local dev)
if [ -f .env ]; then
  # export all variables from .env (simple key=value lines)
  set -o allexport
  # shellcheck disable=SC1091
  source .env
  set +o allexport
  # refresh DOCKER_REGISTRY if set by .env and not overridden by CLI/env
  DOCKER_REGISTRY="${DOCKER_REGISTRY:-${DOCKER_REGISTRY}}"
fi

# Trim whitespace (if any)
if [ -n "${DOCKER_REGISTRY:-}" ]; then
  DOCKER_REGISTRY="$(echo "$DOCKER_REGISTRY" | xargs)"
fi

if [ -z "${DOCKER_REGISTRY:-}" ]; then
  # Uncomment and set the line below to use a default registry (if you want)
  # DOCKER_REGISTRY=localhost:5000
  echo "INFO: DOCKER_REGISTRY not set. Images will be built locally only."
  echo "INFO: To push to a registry, set DOCKER_REGISTRY environment variable or use -r:"
  echo "      export DOCKER_REGISTRY=localhost:5000"
  echo "      or"
  echo "      ./build.sh -r localhost:5000"
  echo ""
else
  echo "INFO: Using DOCKER_REGISTRY='${DOCKER_REGISTRY}'"
fi

VER="$(cat version.txt)"
echo "Building images with version: ${VER}"
if [ -n "${DOCKER_REGISTRY:-}" ]; then
  echo "Registry: ${DOCKER_REGISTRY}"
fi
echo ""

# Optional: Remove existing pgcluster volumes to start fresh
# docker volume ls | grep pgcluster | awk '{print $2}' | xargs docker volume rm 2>/dev/null || true

echo "==> Building PostgreSQL image..."
docker build -t pg:${VER} --no-cache -f postgres/Dockerfile ./postgres
echo "✓ Successfully built pg:${VER}"

if [ -n "${DOCKER_REGISTRY:-}" ]; then
  echo "==> Pushing pg:${VER} to registry ${DOCKER_REGISTRY}..."
  docker tag pg:${VER} "${DOCKER_REGISTRY}/pg:${VER}"
  docker push "${DOCKER_REGISTRY}/pg:${VER}"
  echo "✓ Successfully pushed ${DOCKER_REGISTRY}/pg:${VER}"
fi

echo ""
echo "==> Building Pgpool image..."
docker build -t pgpool:${VER} --no-cache -f pgpool/Dockerfile ./pgpool
echo "✓ Successfully built pgpool:${VER}"

if [ -n "${DOCKER_REGISTRY:-}" ]; then
  echo "==> Pushing pgpool:${VER} to registry ${DOCKER_REGISTRY}..."
  docker tag pgpool:${VER} "${DOCKER_REGISTRY}/pgpool:${VER}"
  docker push "${DOCKER_REGISTRY}/pgpool:${VER}"
  echo "✓ Successfully pushed ${DOCKER_REGISTRY}/pgpool:${VER}"
fi

echo ""
echo "==> Building Manager image..."
thisdir="$(pwd)"
cd manager/build

# Pass DOCKER_REGISTRY to manager build script
export DOCKER_REGISTRY
./build.bash

cd "$thisdir"
echo "✓ Successfully built manager:${VER}"

echo ""
echo "=== Build Summary ==="
echo "Version: ${VER}"
echo "Images built:"
echo "  - pg:${VER}"
echo "  - pgpool:${VER}"
echo "  - manager:${VER}"

if [ -n "${DOCKER_REGISTRY:-}" ]; then
  echo ""
  echo "Images pushed to registry: ${DOCKER_REGISTRY}"
  echo ""
  echo "To verify images in registry (if registry supports v2 catalog):"
  echo "  curl http://${DOCKER_REGISTRY}/v2/_catalog"
else
  echo ""
  echo "Images built locally. To push to a registry:"
  echo "  export DOCKER_REGISTRY=localhost:5000"
  echo "  ./build.sh -r localhost:5000"
fi

echo ""
echo "=== Next Steps ==="
echo "See DEPLOYMENT.md for deployment instructions"
echo ""
