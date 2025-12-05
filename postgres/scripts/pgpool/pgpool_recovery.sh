#!/bin/bash

# This script erase an existing replica and re-base it based on
# the current primary node. Parameters are position-based and include:
#
# 1 - Path to primary database directory.
# 2 - Host name of new node.
# 3 - Path to replica database directory
#
# Be sure to set up public SSH keys and authorized_keys files.
# this script must be in PGDATA
PGVER=${PGVER:-12}
PATH=$PATH:/usr/lib/postgresql/${PGVER}/bin
ARCHIVE_DIR=/archive

if [ ! -d /var/log/pg ] ; then
 sudo mkdir -p /var/log/pg
 sudo chown postgres:postgres /var/log/pg
fi
LOGFILE=/var/log/pg/pgpool_recovery.log
if [ ! -f $LOGFILE ] ; then
 > $LOGFILE
fi

echo "Exec pgpool_recovery.sh at `date`" | tee -a $LOGFILE

if [ $# -lt 3 ]; then
    echo "Create a replica PostgreSQL from the primary within pgpool."
    echo
    echo "Usage: $0 PRIMARY_PATH HOST_NAME COPY_PATH"
    echo
    exit 1
fi

# Function to check SSH connectivity with retries
check_ssh_connectivity() {
    local host=$1
    local max_retries=3
    local retry_delay=2
    local attempt=1
    
    while [ $attempt -le $max_retries ]; do
        echo "Checking SSH connectivity to $host (attempt $attempt/$max_retries)"
        if ssh -p 222 -n -T -o ConnectTimeout=5 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no postgres@$host "echo 'SSH OK'" > /dev/null 2>&1; then
            echo "SSH connection to $host successful"
            return 0
        fi
        echo "SSH connection to $host failed (attempt $attempt/$max_retries)"
        if [ $attempt -lt $max_retries ]; then
            sleep $retry_delay
        fi
        attempt=$((attempt + 1))
    done
    
    echo "ERROR: Failed to establish SSH connection to $host after $max_retries attempts"
    return 1
fi

# Function to execute SSH command with error handling
ssh_exec() {
    local host=$1
    shift
    local cmd="$@"
    local max_retries=2
    local attempt=1
    
    while [ $attempt -le $max_retries ]; do
        echo "Executing via SSH on $host: $cmd"
        if ssh -p 222 -n -T -o ConnectTimeout=10 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no postgres@$host "$cmd"; then
            return 0
        fi
        echo "SSH command failed (attempt $attempt/$max_retries)"
        if [ $attempt -lt $max_retries ]; then
            sleep 2
        fi
        attempt=$((attempt + 1))
    done
    
    echo "ERROR: SSH command failed after $max_retries attempts: $cmd"
    return 1
fi

#primary_host=$(hostname -i)
primary_host=$NODE_NAME
replica_host=$2
replica_path=$3
(
echo "primary_host: ${primary_host}" 
echo "replica_host: ${replica_host}" 
echo "replica_path: ${replica_path}" 

# Check SSH connectivity before proceeding
if ! check_ssh_connectivity "$replica_host"; then
    echo "FATAL: Cannot establish SSH connection to replica host $replica_host"
    exit 1
fi

echo "Stopping postgres on ${replica_host}"
ssh_exec "$replica_host" "/scripts/pg_stop.sh"
echo "Sleeping 20 seconds after stop"
sleep 20

echo "Delete database and archive directories on ${replica_host}"
ssh_exec "$replica_host" "rm -Rf $replica_path/* ${ARCHIVE_DIR}/*"

echo "Use repmgr on the replica host to force it to sync again"
ssh_exec "$replica_host" "/usr/lib/postgresql/${PGVER}/bin/repmgr -h ${primary_host} --username=repmgr -d repmgr -f /etc/repmgr/${PGVER}/repmgr.conf standby clone -v"

echo "Start database on ${replica_host}"
ssh_exec "$replica_host" "/scripts/pg_start.sh"
echo "Sleeping 20 seconds after start"
sleep 20

echo "Register standby database"
ssh_exec "$replica_host" "/usr/lib/postgresql/${PGVER}/bin/repmgr -f /etc/repmgr/${PGVER}/repmgr.conf standby register -F -v"

echo "Check supervisor status on ${replica_host}"
ssh_exec "$replica_host" "sudo supervisorctl status all"

echo "pgpool_recovery.sh completed successfully at `date`"
) 2>&1 | tee -a ${LOGFILE}
