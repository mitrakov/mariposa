#!/usr/bin/env bash
# PostgreSQL
set -euo pipefail
. utils.sh
. .env

check_env "IS_MASTER"


if [[ "$IS_MASTER" == "true" ]]; then
    check_env "MASTER_HOST"

    log "Starting PostgreSQL..."
    PG_DATA_DIR="/var/lib/postgresql/16/main"

    sudo chown -R postgres:postgres /var/lib/postgresql/16
    if sudo [ ! -f "$PG_DATA_DIR/PG_VERSION" ]; then                                      # sudo needed for real Ubuntu
        log "First time run. Initializing PostgreSQL database..."
        sudo --user postgres /usr/lib/postgresql/16/bin/initdb --pgdata "$PG_DATA_DIR"    # initdb must be run as the postgres user
    else
        info "OK: Database exists in $PG_DATA_DIR"
    fi
    sudo service postgresql start

    HIVE_DB_PASSWORD=$(vault kv get -field=hive secret/hadoop/postgres)
    check_env "HIVE_DB_PASSWORD"
    echo "HIVE_DB_PASSWORD=$HIVE_DB_PASSWORD" >> .env
    USER_EXISTS=$(sudo --user postgres psql --tuples-only --no-align --command="SELECT 1 FROM pg_roles WHERE rolname='hive';")
    if [ "$USER_EXISTS" != "1" ]; then
        log "First time run. Creating 'hive' user and 'metastore_db'..."
        sudo --user postgres psql --command "CREATE USER hive WITH PASSWORD '$HIVE_DB_PASSWORD';"
        sudo --user postgres psql --command "CREATE DATABASE metastore_db OWNER hive;"
        sudo --user postgres psql --command "GRANT ALL PRIVILEGES ON DATABASE metastore_db TO hive;"
        info "PostgreSQL user 'hive' and database 'metastore_db' created"
    else
        info "OK: user 'hive' exists"
    fi

    AIRFLOW_DB_PASSWORD=$(vault kv get -field=airflow secret/hadoop/postgres)
    check_env "AIRFLOW_DB_PASSWORD"
    echo "AIRFLOW_DB_PASSWORD=$AIRFLOW_DB_PASSWORD" >> .env
    USER_EXISTS=$(sudo --user postgres psql --tuples-only --no-align --command="SELECT 1 FROM pg_roles WHERE rolname='airflow';")
    if [ "$USER_EXISTS" != "1" ]; then
        log "First time run. Creating 'airflow' user and 'airflow_db'..."
        sudo --user postgres psql --command "CREATE USER airflow WITH PASSWORD '$AIRFLOW_DB_PASSWORD';"
        sudo --user postgres psql --command "CREATE DATABASE airflow_db OWNER airflow;"
        sudo --user postgres psql --command "GRANT ALL PRIVILEGES ON DATABASE airflow_db TO airflow;"
        info "PostgreSQL user 'airflow' and database 'airflow_db' created"
    else
        info "OK: user 'airflow' exists"
    fi

    HUE_DB_PASSWORD=$(vault kv get -field=hue secret/hadoop/postgres)
    check_env "HUE_DB_PASSWORD"
    echo "HUE_DB_PASSWORD=$HUE_DB_PASSWORD" >> .env
    USER_EXISTS=$(sudo --user postgres psql --tuples-only --no-align --command="SELECT 1 FROM pg_roles WHERE rolname='hue';")
    if [ "$USER_EXISTS" != "1" ]; then
        log "First time run. Creating 'hue' user and 'hue_db'..."
        sudo --user postgres psql --command "CREATE USER hue WITH PASSWORD '$HUE_DB_PASSWORD';"
        sudo --user postgres psql --command "CREATE DATABASE hue_db OWNER hue;"
        sudo --user postgres psql --command "GRANT ALL PRIVILEGES ON DATABASE hue_db TO hue;"
        log "PostgreSQL user 'hue' and database 'hue_db' created."
    else
        info "OK: user 'hue' exists"
    fi
fi
