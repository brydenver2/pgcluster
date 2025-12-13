#!/bin/bash
# Script to refresh pool_passwd file from backend PostgreSQL database
# This can be run on-demand without restarting pgpool
#
# IMPORTANT: For SCRAM authentication, pool_passwd needs passwords in a format
# that pgpool can use. Since we cannot retrieve plain passwords from PostgreSQL,
# this script only updates passwords for users we know the plain password for.
#
# For new users created in PostgreSQL:
# You MUST either:
# 1. Manually add them: pg_enc -m -u username -p
# 2. Store plain passwords securely and add them to this script
# 3. Use enable_pool_hba=on with pool_hba.conf to skip pool_passwd

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

# Read MSLIST passwords
MSLIST=${MSLIST:-myservice}
MSOWNERPWDLIST=${MSOWNERPWDLIST:-myservice_owner}
MSUSERPWDLIST=${MSUSERPWDLIST:-myservice_user}

# Setup pgpass for connections
echo "*:*:repmgr:repmgr:${REPMGRPWD}" > /tmp/.pgpass_refresh
chmod 600 /tmp/.pgpass_refresh
export PGPASSFILE=/tmp/.pgpass_refresh

# Backup existing pool_passwd
if [ -f "${POOL_PASSWD_FILE}" ]; then
  cp ${POOL_PASSWD_FILE} ${POOL_PASSWD_FILE}.bak
  echo "Backed up existing pool_passwd to ${POOL_PASSWD_FILE}.bak"
fi

# Create new pool_passwd file with known users and plain passwords
# For SCRAM authentication, pgpool needs plain passwords or AES encrypted passwords
echo "Recreating pool_passwd with known users..."
> ${POOL_PASSWD_FILE}

# Add known users with plain passwords
echo "postgres:${POSTGRES_PASSWORD}" >> ${POOL_PASSWD_FILE}
echo "repmgr:${REPMGRPWD}" >> ${POOL_PASSWD_FILE}
echo "hcuser:hcuser" >> ${POOL_PASSWD_FILE}
echo "${MSLIST}_owner:${MSOWNERPWDLIST}" >> ${POOL_PASSWD_FILE}
echo "${MSLIST}_user:${MSUSERPWDLIST}" >> ${POOL_PASSWD_FILE}

echo "Added known users: postgres, repmgr, hcuser, ${MSLIST}_owner, ${MSLIST}_user"

# Check for additional users in PostgreSQL and warn if they exist
echo ""
echo "Checking for additional database users..."
ADDITIONAL_USERS=$(ssh -p 222 postgres@${DBHOST} "psql -t -A -c \"select rolname from pg_authid where rolpassword is not null and rolname not in ('postgres', 'repmgr', 'hcuser', '${MSLIST}_owner', '${MSLIST}_user') order by rolname;\"" 2>/dev/null)

if [ ! -z "$ADDITIONAL_USERS" ]; then
  echo ""
  echo "WARNING: Additional users found in PostgreSQL that are NOT in pool_passwd:"
  echo "$ADDITIONAL_USERS"
  echo ""
  echo "These users will NOT be able to authenticate through pgpool!"
  echo ""
  echo "To add them, you must either:"
  echo "  1. Run: pg_enc -m -u <username> -p"
  echo "     Then manually add the output to ${POOL_PASSWD_FILE}"
  echo "  2. Add plain passwords to this script if you know them"
  echo "  3. Enable pool_hba authentication (set enable_pool_hba=on in pgpool.conf)"
  echo ""
fi

# Cleanup temp pgpass
rm -f /tmp/.pgpass_refresh

# Show summary
USER_COUNT=$(grep -c ":" ${POOL_PASSWD_FILE} 2>/dev/null || echo 0)
echo "Pool passwd refresh complete. Total users: ${USER_COUNT}"

# Reload pgpool configuration to pick up changes
echo "Reloading pgpool configuration..."
pgpool reload

echo "Done! Pool passwd file updated and pgpool reloaded."
