#!/bin/sh
#set -x

THISDIR=`pwd`
NOCACHE=true
APPNAME=manager

VERSION=$( cat ../../version.txt )
echo "Building ${APPNAME}:${VERSION}"

rm -rf server client 2>/dev/null
cp -r ../server ./
cp -r ../client ./
rm -rf client/node_modules server/node_modules

docker build --no-cache=${NOCACHE} --file Dockerfile -t ${APPNAME}:${VERSION} .
BUILD_STATUS=$?

if [ $BUILD_STATUS -ne 0 ]; then
  echo "ERROR: Failed to build ${APPNAME}:${VERSION}"
  rm -rf server client 2>/dev/null
  exit 1
fi

# Push to registry if DOCKER_REGISTRY is set
if [ ! -z "$DOCKER_REGISTRY" ]; then
  echo "Pushing ${APPNAME}:${VERSION} to ${DOCKER_REGISTRY}..."
  docker tag ${APPNAME}:${VERSION} ${DOCKER_REGISTRY}/${APPNAME}:${VERSION}
  docker push ${DOCKER_REGISTRY}/${APPNAME}:${VERSION}
  if [ $? -ne 0 ]; then
    echo "ERROR: Failed to push to registry"
    rm -rf server client 2>/dev/null
    exit 1
  fi
  echo "✓ Successfully pushed ${DOCKER_REGISTRY}/${APPNAME}:${VERSION}"
fi

rm -rf server client 2>/dev/null
exit 0
