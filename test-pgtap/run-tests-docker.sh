#!/bin/bash

# Запускает pgtap тесты для указанной версии PostgreSQL
# По умолчанию используется версия DEFAULT_PG_VERSION
# Пример запуска:
# 1) ./run-tests-docker.sh
# 2) ./run-tests-docker.sh 9.6

PG_VERSION="$1"
DEFAULT_PG_VERSION="9.4"

if [ -z $PG_VERSION ]; then
    PG_VERSION="$DEFAULT_PG_VERSION"
fi

CURRENT_DIR="$(dirname $(readlink -f "$0"))"
IMAGE="pgmock-$PG_VERSION"
CONTRAINER="pgmock-$PG_VERSION"
DATABASE="pgmock"
USER="postgres"

log()
{
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $@"
}

build_image()
{
    log "Building image for PostgreSQL $PG_VERSION"
    local DOCKERFILE="$CURRENT_DIR/$PG_VERSION.dockerfile"
    echo "FROM postgres:$PG_VERSION
          RUN apt-get update \
           && apt-get install -y postgresql-$PG_VERSION-pgtap" > "$DOCKERFILE"
    docker build --quiet \
                 --tag "$IMAGE" \
                 --file "$DOCKERFILE" \
                 "$CURRENT_DIR" > /dev/null
    rm "$DOCKERFILE"
    log "Done"
}

run_container()
{
    log "Running container $CONTRAINER"

    docker start "$CONTRAINER" > /dev/null || \
        docker run --detach \
                   --volume "$CURRENT_DIR/../:/pgmock" \
                   --name "$CONTRAINER" "$IMAGE" > /dev/null
    docker exec "$CONTRAINER" \
        psql --user "$USER" \
             --dbname "$DATABASE" \
             --tuples-only \
             --command "create extension if not exists pgtap;" > /dev/null
    local EXIT_CODE="$?"

    while [ "$EXIT_CODE" != "0" ]; do
        log "Waiting PostgreSQL to startup" && sleep 2
        docker exec "$CONTRAINER" \
            psql --user "$USER" \
                 --command "create database $DATABASE"
        docker exec "$CONTRAINER" \
            psql --user "$USER" \
                 --dbname "$DATABASE" \
                 --command "create extension pgtap;"
        EXIT_CODE="$?"
    done

    log "Done"
}

update_extension_sources()
{
    log "Updating extension sources"

    local EXTENSION_DIR="/usr/share/postgresql/$PG_VERSION/extension"
    local EXTENSION_SOURCE_CODE="pgmock--0.2.sql"
    docker exec "$CONTRAINER" bash -c "
        cp /pgmock/pgmock.control $EXTENSION_DIR/
        cp /pgmock/$EXTENSION_SOURCE_CODE $EXTENSION_DIR/"

    docker exec "$CONTRAINER" \
            psql --user "$USER" \
                 --dbname "$DATABASE" \
                 --command "drop extension if exists pgmock;
                            drop schema if exists pgmock cascade;
                            create schema pgmock;
                            create extension pgmock with schema pgmock;"
    log "Done"
}

run_tests()
{
    log "Running test"
    docker exec "$CONTRAINER" \
        pg_prove --user "$USER" \
                 --dbname "$DATABASE" \
                 --ext .sql \
                 /pgmock/test-pgtap/
    log "Done"
}

build_image
run_container
update_extension_sources
run_tests