#!/bin/bash

# Запускает регрессионные тесты
# Пример запуска:
# $./run-regression-tests.sh stretch

DEBIAN_VERSION="$1"
SCRIPT_DIR="`dirname "$0"`"
DOCKER_FILE="$SCRIPT_DIR/$DEBIAN_VERSION.dockerfile"

docker build --file "$DOCKER_FILE" $SCRIPT_DIR

IMAGE_ID=$(docker build -q --file "$DOCKER_FILE" "$SCRIPT_DIR")
CONTAINER_ID=$(docker run -d "$IMAGE_ID")

docker cp "$SCRIPT_DIR"/../../../pgmock "$CONTAINER_ID":/tmp/
docker exec "$CONTAINER_ID" bash \
    -c "cd /tmp/pgmock/ && pg_buildext updatecontrol && autopkgtest . -- null"

docker container rm -f "$CONTAINER_ID"
