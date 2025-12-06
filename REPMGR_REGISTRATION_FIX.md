# Repmgr Registration Fix

## Problem

When PostgreSQL containers were restarted (with existing PGDATA from a volume), the initialization script (`postgres/initdb.sh`) would:
1. Check and create the repmgr user if missing
2. Check and create the repmgr database if missing
3. Check and install the repmgr extension if missing

However, it did **not** check if the node itself was registered in the `repmgr.nodes` metadata table. This caused two related issues:

### Issue 1: repmgrd Failure
The repmgr daemon (repmgrd) would fail to start with the error:
```
[ERROR] no metadata record found for this node - terminating
[HINT] check that 'repmgr (primary|standby|witness) register' was executed for this node
```

### Issue 2: Pgpool Failover Failure
Pgpool's entrypoint script relies on finding the primary node in the repmgr metadata:
```bash
if [ "a$repm_type" == "aprimary" ] ; then
  REPMGR_MASTER=$h
  REPMGR_MASTER_PORT=$p
fi
```

When no nodes were registered, `REPMGR_MASTER` would be empty, causing pgpool to attempt SSH connections to invalid hostnames (using NODE_ID instead of NODE_NAME):
```
Cannot connect to host 12 via ssh
```

## Solution

Added code in `postgres/initdb.sh` to check if the node is registered in the repmgr metadata when the database already exists (during container restart). The fix:

1. **Checks if node is registered**: Queries `repmgr.nodes` table for the current `NODE_ID`
2. **Detects node role**: Uses `pg_is_in_recovery()` to determine if the node is a primary or standby
3. **Registers the node**: Calls `repmgr primary register --force` or `repmgr standby register --force` as appropriate

### Code Changes

```bash
# Check if this node is registered in repmgr metadata
log_info "Checking if node is registered in repmgr metadata"
NODE_REGISTERED=$(psql -d repmgr -tAc "SELECT COUNT(*) FROM repmgr.nodes WHERE node_id=${NODE_ID}")
if [ "$NODE_REGISTERED" = "0" ] ; then
  log_info "Node not registered, registering now"
  # Determine if this is a primary or standby by checking recovery status
  IS_IN_RECOVERY=$(psql -tAc "SELECT pg_is_in_recovery()")
  if [ "$IS_IN_RECOVERY" = "f" ] ; then
    log_info "This node is a primary, registering as primary"
    repmgr -f /etc/repmgr/${PGVER}/repmgr.conf -v primary register --force
    if [ $? -ne 0 ] ; then
      log_info "WARNING: Failed to register node as primary"
    fi
  else
    log_info "This node is a standby, registering as standby"
    repmgr -f /etc/repmgr/${PGVER}/repmgr.conf -v standby register --force
    if [ $? -ne 0 ] ; then
      log_info "WARNING: Failed to register node as standby"
    fi
  fi
else
  log_info "Node already registered in repmgr metadata"
fi
```

## When This Matters

This fix is essential when:
- Containers are restarted after initial setup
- PGDATA is persisted on volumes but the repmgr database content is lost or corrupted
- Rebuilding a cluster from existing PGDATA
- Recovering from backup scenarios where PGDATA exists but metadata is missing

## Testing

The fix ensures that:
1. repmgrd can start successfully on container restart
2. Pgpool can correctly identify the primary node for failover operations
3. The cluster maintains proper metadata consistency across restarts
