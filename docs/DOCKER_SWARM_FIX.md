# Docker Swarm PostgreSQL Cluster Fix

## Executive Summary

Your PostgreSQL cluster was failing to initialize in Docker Swarm due to **three critical issues**:

1. **Primary registration failure** - PostgreSQL started with `listen_addresses=localhost`, preventing repmgr from registering the node
2. **Environment variable misconfiguration** - `PG_MASTER_NODE_NAME` wasn't reading from `PGMASTER` environment variable
3. **Standby initialization failure** - Standbys waited forever for master registration that never completed

## Detailed Analysis

### Issue 1: Primary Node Cannot Register with Repmgr ⚠️ CRITICAL

**Location:** `postgres/initdb.sh` lines 212-224

**Problem:**
```bash
# Old code - started with localhost only
pg_ctl -D ${PGDATA} start -o "-c 'listen_addresses=localhost'" -w
```

The initialization script started PostgreSQL listening only on `localhost`, then attempted to register with repmgr using the hostname `pg01`. Since PostgreSQL wasn't accepting connections on the network interface, the registration failed:

```
ERROR: connection to database failed
connection to server at "pg01" (10.0.4.8), port 5432 failed: Connection refused
```

**Why this matters in Docker Swarm:**
- In Docker Swarm overlay networks, containers resolve each other by hostname (e.g., `pg01`)
- Repmgr uses `conninfo='host=pg01 dbname=repmgr...'` which requires PostgreSQL to listen on all interfaces
- The `pg_hba.conf` already allows connections from `0.0.0.0/0`, but PostgreSQL wasn't listening

**Fix Applied:**
```bash
# New code - listens on all addresses from the start
pg_ctl -D ${PGDATA} start -w
```

Removed `-o "-c 'listen_addresses=localhost'"` from both initialization paths:
- Line ~212: Initial master setup
- Line ~268: Container restart path

This allows PostgreSQL to use the `listen_addresses = '*'` setting from `01custom.conf` immediately.

---

### Issue 2: Environment Variable Not Being Used

**Location:** `postgres/initdb.sh` line ~119

**Problem:**
```bash
# Old code
PG_MASTER_NODE_NAME=${PG_MASTER_NODE_NAME:-pg01}
```

The script had a fallback default but wasn't reading the `PGMASTER` environment variable that's set in `docker-compose-portainer.yml`.

**Why this matters:**
- Docker Compose sets `PGMASTER: pg01` for all nodes
- The script should use this value but was only using its own default
- This caused inconsistencies when the environment variable was set to something else

**Fix Applied:**
```bash
# New code
PG_MASTER_NODE_NAME=${PGMASTER:-pg01}
log_info "PG_MASTER_NODE_NAME: $PG_MASTER_NODE_NAME"
```

Now properly reads from `PGMASTER` env var and logs the value for debugging.

---

### Issue 3: Standby Nodes Wait Forever

**Location:** `postgres/initdb.sh` `wait_for_master()` function

**Problem:**
The `wait_for_master()` function didn't have proper return codes, and didn't provide diagnostic information about DNS resolution in Docker Swarm overlay networks.

From the logs:
```
pg02: waiting for repmgr node to be initialized with the master
pg02: waiting for repmgr node to be initialized with the master
[repeats forever...]
```

**Root Cause Chain:**
1. Primary (pg01) fails to register with repmgr (Issue #1)
2. Standby nodes (pg02, pg03) query `repmgr.nodes` table
3. Table is empty because primary never registered
4. Standbys loop forever waiting for a node to appear

**Fix Applied:**

1. **Added explicit return codes:**
```bash
# Return success if we found at least one node, failure otherwise
if [ $nbrlines -ge 1 ] ; then
  log_info "Master has $nbrlines nodes registered, proceeding with standby setup"
  return 0
else
  log_info "Master has no nodes registered after waiting, cannot proceed"
  return 1
fi
```

2. **Added DNS resolution diagnostics:**
```bash
# First, check DNS resolution
log_info "Checking DNS resolution for ${HOST}"
if ! getent hosts ${HOST} > /dev/null 2>&1 ; then
  log_info "WARNING: Cannot resolve hostname ${HOST}, waiting for DNS..."
  # Wait a bit for DNS to be available
  for i in 1 2 3 4 5; do
    sleep 2
    if getent hosts ${HOST} > /dev/null 2>&1 ; then
      log_info "DNS resolution for ${HOST} succeeded"
      break
    fi
  done
else
  log_info "DNS resolution for ${HOST} successful: $(getent hosts ${HOST})"
fi
```

This helps diagnose Docker Swarm overlay network issues where DNS might not be immediately available.

---

## Impact on Other Components

### Pgpool Behavior

**Before fixes:**
- Pgpool would wait for nodes in `repmgr.nodes` table
- Found 0 nodes because primary never registered
- Set `REPMGR_MASTER=""` (empty)
- Attempted to connect to node ID instead of hostname: `Is DB up for host 12 port 5432 ?`
- Failed to start properly

**After fixes:**
- Primary successfully registers in `repmgr.nodes`
- Pgpool finds the primary node
- Sets `REPMGR_MASTER=pg01` correctly
- Connects to proper hostname
- Functions normally

### Repmgrd (Replication Manager Daemon)

**Before fixes:**
```
[ERROR] no metadata record found for this node - terminating
[HINT] check that 'repmgr (primary|standby|witness) register' was executed
```

**After fixes:**
- Nodes are properly registered in `repmgr.nodes`
- Repmgrd starts successfully
- Can monitor replication health
- Manual/automatic failover works as configured

---

## Testing the Fixes

### Prerequisites
1. Rebuild the Docker images with the updated `initdb.sh`:
   ```bash
   cd /Users/bwallace/Documents/GitHub/pgcluster
   ./build.sh
   ```

2. Push to your registry:
   ```bash
   docker tag pg:1.0.1 registry.local.wallacearizona.us/pg:1.0.1
   docker push registry.local.wallacearizona.us/pg:1.0.1
   ```

### Deployment Steps

1. **Clean existing volumes (ONLY if starting fresh):**
   ```bash
   docker stack rm pgcluster
   # Wait for services to stop
   docker volume rm pgcluster_pg01db pgcluster_pg02db pgcluster_pg03db
   docker volume rm pgcluster_pg01arc pgcluster_pg02arc pgcluster_pg03arc
   ```

2. **Deploy the stack:**
   ```bash
   docker stack deploy -c docker-compose-portainer.yml pgcluster
   ```

3. **Monitor the logs:**
   ```bash
   # Watch all services
   docker service logs -f pgcluster_pg01
   docker service logs -f pgcluster_pg02
   docker service logs -f pgcluster_pg03
   docker service logs -f pgcluster_pgpool
   ```

### What to Look For

#### ✅ Success Indicators

**pg01 (Primary):**
```
INFO - Start initdb on host pg01
INFO - PG_MASTER_NODE_NAME: pg01
INFO - This node is the master or we are in a single db setup
INFO - Register master in repmgr
INFO - registered node 1 "pg01" (ID: 1) as primary
INFO - start postgres in foreground
```

**pg02/pg03 (Standbys):**
```
INFO - This is a slave. Wait that master is up and running
INFO - waiting for master on pg01 to be ready
INFO - DNS resolution for pg01 successful: 10.0.4.8 pg01
waiting for repmgr node to be initialized with the master
INFO - Master has 1 nodes registered, proceeding with standby setup
NOTICE: standby clone (using pg_basebackup) complete
INFO - standby registered with node ID 2
```

**pgpool:**
```
repmgr_master is pg01
master database is up
backend pg01 is up in repl_nodes
backend pg02 is up in repl_nodes
backend pg03 is up in repl_nodes
```

**repmgrd:**
```
[NOTICE] repmgrd (repmgrd 5.5.0) starting up
[INFO] connecting to database "host=pg01 dbname=repmgr..."
[NOTICE] monitoring cluster primary "pg01" (node ID: 1)
```

#### ❌ Failure Indicators (if they still occur)

1. **Primary registration fails:**
   ```
   ERROR: connection to database failed
   connection to server at "pg01" (10.0.4.8), port 5432 failed
   ```
   - Check firewall rules
   - Verify overlay network is working: `docker network inspect pgcluster_pgcluster_network`

2. **DNS resolution fails:**
   ```
   WARNING: Cannot resolve hostname pg01, waiting for DNS...
   ```
   - Docker Swarm DNS issues
   - Check service discovery: `docker service ps pgcluster_pg01`

3. **Standbys timeout:**
   ```
   Master has no nodes registered after waiting, cannot proceed
   ```
   - Primary didn't register (check pg01 logs first)
   - Network connectivity issue between containers

---

## Docker Swarm Specific Considerations

### Overlay Network
The `pgcluster_network` uses:
- Driver: `overlay` with encryption
- Attachable: `true`
- DNS-based service discovery

**Important:** Overlay networks can have a brief DNS propagation delay. The added DNS checks help handle this.

### Node Placement Constraints
Your setup pins each PostgreSQL node to a specific Docker Swarm node:
```yaml
placement:
  constraints:
    - node.labels.postgres.node == pg01
```

**Verify labels exist:**
```bash
docker node ls
docker node inspect <node-name> | grep -A5 Labels
```

**Add labels if missing:**
```bash
docker node update --label-add postgres.node=pg01 <node-name-1>
docker node update --label-add postgres.node=pg02 <node-name-2>
docker node update --label-add postgres.node=pg03 <node-name-3>
```

### Port Publishing Mode
Using `mode: host` for PostgreSQL ports means:
- Ports 15432, 25432, 35432 are published on the swarm nodes directly
- Services must run on different nodes (enforced by constraints)
- Direct connection bypasses the swarm routing mesh

---

## Troubleshooting Commands

### Check Service Status
```bash
docker stack ps pgcluster --no-trunc
```

### View Service Logs
```bash
docker service logs pgcluster_pg01 --tail 100
docker service logs pgcluster_pg02 --tail 100
docker service logs pgcluster_pg03 --tail 100
docker service logs pgcluster_pgpool --tail 100
```

### Connect to Running Container
```bash
# Find the container
docker ps | grep pg01

# Enter the container
docker exec -it <container-id> bash

# Check PostgreSQL status
su - postgres
pg_ctl status -D /data

# Check repmgr
repmgr -f /etc/repmgr/17/repmgr.conf cluster show
```

### Query Repmgr Status
```bash
# From pg01
docker exec -it $(docker ps -q -f name=pgcluster_pg01) su - postgres -c \
  "psql -d repmgr -c 'SELECT * FROM repmgr.nodes;'"
```

### Check Network Connectivity
```bash
# DNS resolution
docker exec -it <container-id> getent hosts pg01
docker exec -it <container-id> getent hosts pg02

# Ping test
docker exec -it <container-id> ping -c 3 pg01

# PostgreSQL connectivity
docker exec -it <container-id> su - postgres -c \
  "psql -h pg01 -U repmgr -d repmgr -c 'SELECT 1;'"
```

---

## Additional Recommendations

### 1. Health Checks
Consider adding Docker health checks to your compose file:
```yaml
healthcheck:
  test: ["CMD-SHELL", "pg_isready -U postgres"]
  interval: 10s
  timeout: 5s
  retries: 5
```

### 2. Logging
Your current setup logs to stdout/stderr. Consider:
- Centralized logging (ELK, Loki, etc.)
- Log retention policies
- Structured logging formats

### 3. Monitoring
Set up monitoring for:
- Replication lag (`repmgr cluster show`)
- Connection pools (pgpool stats)
- Database size and performance
- Container resource usage

### 4. Backup Strategy
Ensure you have:
- Regular pg_basebackup jobs
- WAL archiving to external storage
- Tested restore procedures
- Off-site backup copies

### 5. Failover Testing
Once cluster is stable:
1. Test manual failover: `docker service scale pgcluster_pg01=0`
2. Verify pgpool detects failure
3. Verify repmgr promotes standby
4. Test application connectivity through pgpool
5. Test recovery of failed node

---

## Summary of Changes Made

### Files Modified
1. **`postgres/initdb.sh`** - Three changes:
   - Removed `listen_addresses=localhost` restriction (2 locations)
   - Fixed `PG_MASTER_NODE_NAME` to read from `PGMASTER` env var
   - Added DNS resolution checks and proper return codes in `wait_for_master()`

### Files Not Modified (but relevant)
- `docker-compose-portainer.yml` - Already correct, sets `PGMASTER: pg01`
- `postgres/pgconfig/01custom.conf` - Already has `listen_addresses = '*'`
- `postgres/supervisord.conf` - Correctly manages postgres and repmgr processes

---

## Expected Outcome

After applying these fixes and rebuilding:

1. **pg01** starts and successfully registers as primary in repmgr
2. **pg02** and **pg03** detect the registered primary and clone themselves as standbys
3. **pgpool** finds the primary and all standbys in `repmgr.nodes`
4. **repmgrd** daemons start successfully on all nodes
5. Cluster is fully operational and ready for connections through pgpool on port 9999

The logs will show clear progression through each step, making it easy to verify proper operation or identify any remaining issues.

---

## Questions or Issues?

If problems persist after applying these fixes, check:

1. **Docker Swarm node labels** - Are they set correctly?
2. **Network connectivity** - Can containers reach each other?
3. **Firewall rules** - Blocking ports 5432, 222, 9999?
4. **Image versions** - Did you rebuild and push the updated image?
5. **Volume cleanup** - Old data might cause issues, consider clean start

Collect logs using:
```bash
mkdir -p logs
docker service logs pgcluster_pg01 > logs/pg01.log 2>&1
docker service logs pgcluster_pg02 > logs/pg02.log 2>&1
docker service logs pgcluster_pg03 > logs/pg03.log 2>&1
docker service logs pgcluster_pgpool > logs/pgpool.log 2>&1
```
