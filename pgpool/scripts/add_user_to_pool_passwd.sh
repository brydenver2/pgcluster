#!/bin/bash
# Script to add a user to pool_passwd file
# Usage: ./add_user_to_pool_passwd.sh <username> <password>

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <username> <password>"
  echo ""
  echo "Example: $0 myuser mypassword"
  echo ""
  echo "This script adds a user with their plain password to pool_passwd."
  echo "For SCRAM authentication, pgpool needs plain passwords."
  exit 1
fi

USERNAME=$1
PASSWORD=$2

CONFIG_DIR=/etc/pgpool-II
POOL_PASSWD_FILE=${CONFIG_DIR}/pool_passwd

# Backup existing pool_passwd
if [ -f "${POOL_PASSWD_FILE}" ]; then
  cp ${POOL_PASSWD_FILE} ${POOL_PASSWD_FILE}.bak
  echo "Backed up existing pool_passwd to ${POOL_PASSWD_FILE}.bak"
fi

# Remove existing entry for this user if it exists
sed -i -e "/^${USERNAME}:/d" ${POOL_PASSWD_FILE}

# Add the user with plain password
echo "${USERNAME}:${PASSWORD}" >> ${POOL_PASSWD_FILE}

echo "Added user '${USERNAME}' to pool_passwd"
echo ""
echo "Now reloading pgpool configuration..."
pgpool reload

echo ""
echo "Done! User '${USERNAME}' can now authenticate through pgpool."
echo ""
echo "SECURITY NOTE: The password is stored in plain text in ${POOL_PASSWD_FILE}"
echo "Ensure this file has appropriate permissions (should be 600 or 640)."
