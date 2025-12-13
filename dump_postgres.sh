#!/bin/bash

# Script to dump all roles, users, databases, and tablespaces from PostgreSQL 17.5
# Run this on your OLD PostgreSQL server
# Usage: ./dump_postgres.sh [pg_dumpall options]
# Example: ./dump_postgres.sh -h localhost -U postgres

# Set default connection parameters (modify as needed)
PGHOST=${PGHOST:-localhost}
PGPORT=${PGPORT:-5432}
PGUSER=${PGUSER:-postgres}
PGPASSWORD=${PGPASSWORD:-}  # Set if needed, or use .pgpass

# Directory to store dumps
DUMP_DIR="./postgres_dump_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$DUMP_DIR"

echo "Dumping PostgreSQL data to $DUMP_DIR"

# Dump global objects (roles, tablespaces)
echo "Dumping roles and tablespaces..."
pg_dumpall --globals-only --host="$PGHOST" --port="$PGPORT" --username="$PGUSER" "$@" > "$DUMP_DIR/globals.sql"

# Get list of databases (excluding template databases)
DATABASES=$(psql --host="$PGHOST" --port="$PGPORT" --username="$PGUSER" "$@" -t -c "SELECT datname FROM pg_database WHERE datistemplate = false AND datname != 'postgres';")

# Dump the 'postgres' database separately if needed
echo "Dumping postgres database..."
pg_dump --host="$PGHOST" --port="$PGPORT" --username="$PGUSER" "$@" --create --clean postgres > "$DUMP_DIR/postgres.sql"

# Dump each user database
for DB in $DATABASES; do
    echo "Dumping database: $DB"
    pg_dump --host="$PGHOST" --port="$PGPORT" --username="$PGUSER" "$@" --create --clean "$DB" > "$DUMP_DIR/${DB}.sql"
done

echo "Dump complete. Files in $DUMP_DIR:"
ls -la "$DUMP_DIR"

echo ""
echo "To restore on the new server:"
echo "1. Copy the $DUMP_DIR directory to the new server"
echo "2. Restore globals: psql -f $DUMP_DIR/globals.sql"
echo "3. Restore each database: psql -f $DUMP_DIR/<dbname>.sql"
echo "Note: You may need to adjust connection parameters and ensure the new server is ready."