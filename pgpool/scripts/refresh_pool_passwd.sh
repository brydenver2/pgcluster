#!/bin/bash
# Script to refresh pool_passwd file from backend PostgreSQL database
# This can be run on-demand without restarting pgpool

CONFIG_DIR=/etc/pgpool-II
POOL_PASSWD_FILE=${CONFIG_DIR}/pool_passwd

# Get the master node from environment or find it
if [ -z "${PGMASTER_NODE_NAME}" ]; then
  echo "PGMASTER_NODE_NAME not set, trying to detect primary..."
  # Try to find primary from backend list
  IFS=',' read -ra PG_HOSTS <<< "$PG_BACKEND_NODE_LIST"
  DBHOST=$(echo ${PG_HOSTS[0]} | cut -f2 -d":")
else
  DBHOST=${PGMASTER_NODE_NAME}
fi

echo "Refreshing pool_passwd from ${DBHOST}..."

# Read REPMGRPWD from file or environment (needed for psql connection)
if [ ! -z "${REPMGRPWD_FILE}" ] && [ -f "${REPMGRPWD_FILE}" ] ; then
  REPMGRPWD=$(cat ${REPMGRPWD_FILE} | tr -d '\n\r' | xargs)
else
  REPMGRPWD=${REPMGRPWD:-rep123}
fi

# Read POSTGRES_PASSWORD from file or environment
if [ ! -z "${POSTGRES_PASSWORD_FILE}" ] && [ -f "${POSTGRES_PASSWORD_FILE}" ] ; then
  POSTGRES_PASSWORD=$(cat ${POSTGRES_PASSWORD_FILE} | tr -d '\n\r' | xargs)
else
  POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-${REPMGRPWD}}
fi

# Setup pgpass for connections
echo "*:*:repmgr:repmgr:${REPMGRPWD}" > /tmp/.pgpass_refresh
chmod 600 /tmp/.pgpass_refresh
export PGPASSFILE=/tmp/.pgpass_refresh

# Backup existing pool_passwd
if [ -f "${POOL_PASSWD_FILE}" ]; then
  cp ${POOL_PASSWD_FILE} ${POOL_PASSWD_FILE}.bak
  echo "Backed up existing pool_passwd to ${POOL_PASSWD_FILE}.bak"
fi

# Create new pool_passwd file
touch ${POOL_PASSWD_FILE}

# Note: We don't manually add postgres here - it will be fetched from pg_authid below
# This ensures the hash matches what's in PostgreSQL (SCRAM-SHA-256 or other)

# Fetch all user passwords from backend database via SSH
echo "Fetching user passwords from ${DBHOST}..."
ssh -p 222 postgres@${DBHOST} "psql -t -A -c \"select rolname || ':' || rolpassword from pg_authid where rolpassword is not null;\"" 2>/dev/null | while IFS=: read f1 f2
do
  # Only add if password hash exists and starts with md5 or SCRAM
  if [[ "$f2" =~ ^(md5|SCRAM-SHA-256) ]]; then
    echo "Adding user: $f1"
    sed -i -e "/^${f1}:/d" ${POOL_PASSWD_FILE}
    echo "$f1:$f2" >> ${POOL_PASSWD_FILE}
  fi
done

# Cleanup temp pgpass
rm -f /tmp/.pgpass_refresh

# Show summary
USER_COUNT=$(grep -c ":" ${POOL_PASSWD_FILE} 2>/dev/null || echo 0)
echo "Pool passwd refresh complete. Total users: ${USER_COUNT}"

# Reload pgpool configuration to pick up changes
echo "Reloading pgpool configuration..."
pgpool reload

echo "Done! Pool passwd file updated and pgpool reloaded."
