#!/bin/bash

# Производит сборку и тестировние deb-пакетов для расширения
# Собранные deb-пакеты доступны в директории packages
# Пример запуска:
# $./build-deb-packages.sh jessie

DEBIAN_VERSION="$1"
SCRIPT_DIR="`dirname "$0"`"
DOCKER_FILE="$SCRIPT_DIR/$DEBIAN_VERSION.dockerfile"

docker build --file "$DOCKER_FILE" $SCRIPT_DIR

IMAGE_ID=$(docker build -q --file "$DOCKER_FILE" "$SCRIPT_DIR")
CONTAINER_ID=$(docker run -d "$IMAGE_ID")

docker cp "$SCRIPT_DIR"/../../../pgmock "$CONTAINER_ID":/tmp/
docker exec "$CONTAINER_ID" bash -c "
       cd /tmp/pgmock/ \
    && pg_buildext updatecontrol \
    && debuild -uc -us \
    && cd /tmp/ \
    && autopkgtest -B *.deb pgmock/ -- null \
    && mkdir $DEBIAN_VERSION \
    && mv *.deb $DEBIAN_VERSION/"

PACKAGE_DIR="$SCRIPT_DIR/packages"
rm -rf "$PACKAGE_DIR/$DEBIAN_VERSION"
mkdir -p "$PACKAGE_DIR/$DEBIAN_VERSION"

docker cp "$CONTAINER_ID:/tmp/$DEBIAN_VERSION" "$PACKAGE_DIR"

docker container rm -f "$CONTAINER_ID"
