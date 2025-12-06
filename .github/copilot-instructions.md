# GitHub Copilot Instructions for pgcluster

## Project Overview

This is a PostgreSQL high-availability cluster project using Docker containers. The system provides:
- PostgreSQL 17 streaming replication with automated failover
- Pgpool-II 4.6 for connection pooling and load balancing
- repmgr 5.5 for replication management
- A Node.js/React web-based management interface
- Support for Docker Swarm and standalone deployments

**Base OS**: Debian 12 (Bookworm)

## Architecture

### Components

1. **postgres/** - PostgreSQL database containers
   - Includes PostgreSQL 17, repmgr, SSH server, and supervisord
   - Streaming replication configured between master and slave nodes
   - Scripts for backup, restore, failover, and monitoring

2. **pgpool/** - Pgpool-II connection pooler
   - Connection pooling and load balancing
   - Watchdog mode for high availability with VIP
   - Automatic failover capabilities

3. **manager/** - Web-based management interface
   - **server/** - Node.js/Express backend API
   - **client/** - React/Redux frontend application
   - Real-time monitoring via WebSockets
   - Operations: failover, switchover, backups

4. **ansible/** - Deployment automation
   - Ansible playbooks for multi-node cluster deployment
   - Support for watchdog mode configuration

5. **tests/** - Testing scripts
   - Shell scripts for testing different deployment scenarios

## Technology Stack

### Backend (manager/server)
- **Language**: JavaScript (Node.js)
- **Framework**: Express.js
- **Database Client**: node-postgres (pg)
- **WebSocket**: express-ws
- **Testing**: Jest, Mocha, Chai
- **Linting**: ESLint with Airbnb style guide

### Frontend (manager/client)
- **Framework**: React 16.x
- **State Management**: Redux with redux-thunk
- **UI Framework**: React Bootstrap 3
- **Build Tool**: react-scripts (Create React App)
- **Testing**: Jest, Enzyme
- **Styling**: Bootstrap 3 with SASS

### Infrastructure
- **Containerization**: Docker
- **Orchestration**: Docker Compose, Docker Swarm
- **Shell Scripts**: Bash (for automation and operations)
- **Database**: PostgreSQL 17
- **Replication**: repmgr 5.5
- **Connection Pooling**: Pgpool-II 4.6

## Code Conventions

### JavaScript (Node.js Backend)

- **Style Guide**: Airbnb JavaScript Style Guide
- **Linting**: ESLint with `airbnb-base` config
- **Quotes**: Single quotes preferred, avoid escape when possible
- **Module System**: CommonJS (`require`/`module.exports`)
- **File Structure**:
  - `routes/` - Express route handlers
  - `DAO/` - Data Access Objects for database operations
  - `business/` - Business logic layer
  - `config/` - Configuration management

Example patterns:
```javascript
const express = require('express');
const router = express.Router();

router.get('/api/resource', (req, res) => {
  // Handler logic
});

module.exports = router;
```

### JavaScript (React Frontend)

- **Component Style**: Class components with lifecycle methods
- **PropTypes**: Used for prop validation
- **State Management**: Redux with actions and reducers
- **File Structure**:
  - Components organized by feature (health/, postgres/, docker/, etc.)
  - Each feature has: `components/`, `actions/`, `reducers/`, `api/`
- **Styling**: Component-specific CSS files, Bootstrap classes

Example patterns:
```javascript
import React, { Component } from 'react';
import PropTypes from 'prop-types';

class MyComponent extends Component {
  componentDidMount() {
    this.props.fetchData();
  }

  render() {
    return <div>{/* JSX */}</div>;
  }
}

MyComponent.propTypes = {
  fetchData: PropTypes.func.isRequired
};

export default MyComponent;
```

### Shell Scripts

- **Shebang**: Always use `#!/bin/bash`
- **Error Handling**: Use `set -e` when appropriate, explicit exit codes
- **User Context**: Scripts often run as postgres user via `su - postgres -c`
- **Sudo**: Postgres user has passwordless sudo access
- **Paths**: Use absolute paths, especially `/scripts/`, `/data/`, `/archive/`
- **Environment Variables**: Heavily used for configuration

Common patterns:
```bash
#!/bin/bash
# Brief description of what the script does

# Exit on error
set -e

# Run as postgres user
su - postgres -c "psql -c \"SELECT version();\""

# Exit with status
exit $?
```

### Docker

- **Base Images**: debian:12 for all containers
- **User Management**: 
  - postgres user (uid 50010, gid 50010)
  - Postgres user has sudo access
- **Networking**: Overlay networks for swarm, bridge for standalone
- **Volumes**: Named volumes for persistence (/data, /archive, /backup)
- **Environment Variables**: Extensive use for runtime configuration

Key environment variables:
- `PG_BACKEND_NODE_LIST` - CSV list of backend PostgreSQL nodes
- `NODE_ID`, `NODE_NAME` - Node identification
- `INITIAL_NODE_TYPE` - master or slave
- `REPMGRPWD` - repmgr user password
- `PGMASTER` - Master node hostname
- `FAILOVER_MODE` - automatic or manual

### Docker Compose

- **Version**: 3.2
- **Service Naming**: pg01, pg02, pg03 for postgres nodes; pgpool for connection pooler
- **Port Mapping**: 
  - PostgreSQL: 15432, 25432, 35432 (host) → 5432 (container)
  - Pgpool: 9999:9999
  - Manager: 8080:8080
- **Dependencies**: Use `depends_on` for startup order
- **Networks**: Custom overlay or bridge networks

**Note on Terminology**: This project uses "master/slave" terminology for historical reasons and compatibility with existing PostgreSQL documentation and tooling. Modern PostgreSQL prefers "primary/replica" or "primary/standby" terminology.

## File Organization

```
pgcluster/
├── .github/              # GitHub-specific files (workflows, copilot instructions)
├── ansible/              # Ansible playbooks for deployment
├── doc/                  # Documentation (architecture, scenarios)
├── manager/              # Management web application
│   ├── build/           # Build scripts and Dockerfile
│   ├── client/          # React frontend application
│   │   └── src/        # Source code organized by feature
│   └── server/          # Node.js backend API
│       ├── DAO/        # Database access layer
│       ├── business/   # Business logic
│       ├── config/     # Configuration
│       └── routes/     # Express routes
├── pgpool/              # Pgpool-II container
│   ├── bin/            # Entry point scripts
│   ├── scripts/        # Operational scripts
│   └── Dockerfile      # Container definition
├── postgres/            # PostgreSQL container
│   ├── pgconfig/       # PostgreSQL configuration templates
│   ├── queries/        # SQL queries and scripts
│   ├── scripts/        # Operational scripts (backup, restore, failover)
│   │   ├── lib/       # Shared utility scripts
│   │   ├── monitor/   # Health check scripts
│   │   └── pgpool/    # Pgpool integration scripts
│   ├── ssh_keys/       # SSH keys for inter-node communication
│   └── Dockerfile      # Container definition
├── tests/               # Test scripts and Docker Compose files
├── build.sh            # Main build script for all images
├── docker-compose*.yml  # Various deployment configurations
├── QUICKSTART.md       # Quick start guide
├── DEPLOYMENT.md       # Comprehensive deployment guide
├── README.md           # Main documentation
└── version.txt         # Current version number
```

## Development Workflow

### Building Images

```bash
# Build all images locally
./build.sh

# Build and push to registry
export DOCKER_REGISTRY=localhost:5000
./build.sh
```

### Local Development

For backend development:
```bash
cd manager/server
export PG_BACKEND_NODE_LIST="0:pg01:5432:1:/u01/pg17/data:ALLOW_TO_FAILOVER,1:pg02:5432:1:/u01/pg17/data:ALLOW_TO_FAILOVER"
export REPMGRPWD=rep123
npm start
```

For frontend development:
```bash
cd manager/client
export REACT_APP_SERVERIP=<server-ip>
npm start
```

### Testing

Backend tests:
```bash
cd manager/server
npm test
```

Frontend tests:
```bash
cd manager/client
npm test
```

Integration tests:
```bash
cd tests
./test_pgpool.sh
```

### Linting

```bash
# Backend
cd manager/server
npm run lint

# Frontend
cd manager/client
npm run lint
```

## Deployment Modes

### 1. Standalone Test (Single Docker Host)
- Use `docker-compose-test.yml`
- Creates bridge network
- Good for development and testing

### 2. Docker Swarm with Watchdog
- Use `docker-compose.yml`
- Each service pinned to specific swarm node
- Pgpool in watchdog mode with VIP

### 3. Portainer Deployment
- Use `docker-compose-portainer.yml`
- Deploy via Portainer UI
- Requires registry for image distribution

### 4. Non-Swarm Watchdog (Traditional HA)
- See `doc/pgpoolwatchdog.md`
- Pgpool watchdog with virtual IP
- More traditional high-availability setup

## Important Concepts

### PostgreSQL Replication
- **Streaming Replication**: Asynchronous by default
- **Replication Slots**: Used for WAL management
- **repmgr**: Manages replication topology and metadata
- **Automatic Failover**: Can be handled by pgpool OR repmgr
  - Pgpool is recommended for better integration with connection pooling
  - Provides more stable failover behavior in production environments
- **Network Configuration**: 
  - PostgreSQL must listen on all interfaces (`listen_addresses='*'`) for repmgr to work in Docker Swarm
  - Configuration in `postgres/pgconfig/01custom.conf` sets `listen_addresses = '*'`
  - DO NOT override with `listen_addresses=localhost` during startup in Docker Swarm environments
  - Repmgr uses hostname-based connections (e.g., `host=pg01`) which require network listening

### Pgpool Configuration
- **Backend Node List**: Defines all PostgreSQL nodes
- **Watchdog Mode**: Provides pgpool HA with VIP
- **Health Checks**: Regular checks on backend nodes
- **Failover Scripts**: Custom scripts executed during failover
- **Pool Status**: Stored in `/tmp/pgpool_status` or host-mounted directory

### SSH and Security
- SSH keys pre-generated for inter-node communication
- SSH runs on port 222 (not default 22)
- Postgres user has sudo access for operations
- StrictHostKeyChecking disabled for container-to-container SSH

### Data Persistence
- **PGDATA**: `/data` - Main database directory
- **Archive**: `/archive` - WAL archive location
- **Backup**: `/backup` - Backup storage location
- All three are Docker volumes for persistence

## Common Operations

### Check Cluster Status
```bash
docker exec -it <container> su - postgres -c "repmgr cluster show"
```

### Manual Failover
```bash
# Via pgpool PCP
pcp_promote_node -h localhost -p 9898 -U postgres -n <node_id>

# Via repmgr
repmgr standby promote -f /etc/repmgr.conf
```

### Backup and Restore
```bash
# Backup
/scripts/backup.sh

# Restore
/scripts/restore.sh <backup_id>
```

### View Logs
```bash
# Container logs
docker logs <container_name>

# PostgreSQL logs
docker exec -it <container> tail -f /data/log/postgresql-*.log

# Pgpool logs
docker exec -it <container> tail -f /var/log/pgpool/pgpool.log
```

## Code Generation Guidelines

When generating code for this project:

1. **Match Existing Patterns**: Follow the established patterns in similar files
2. **Use Appropriate Style**: 
   - Airbnb style for JavaScript
   - Standard Bash practices for shell scripts
3. **Include Error Handling**: 
   - Try-catch for async operations
   - Exit codes for shell scripts
4. **Environment Variables**: Use for configuration, don't hardcode values
5. **Documentation**: Add comments for complex logic, especially in shell scripts
6. **Testing**: Write tests for new functionality (Jest for JS, shell scripts for integration)
7. **Docker Best Practices**: 
   - Minimize layer count
   - Clean up apt cache
   - Use specific versions
   - For Docker Swarm: ensure services listen on all interfaces, not just localhost
   - Consider DNS propagation delays in overlay networks
8. **Security**: 
   - Never commit secrets
   - Use environment variables for passwords
   - Validate inputs

## Recent Fixes (December 2025)

### Docker Swarm Repmgr Registration Fix

**Issue**: Primary PostgreSQL node failed to register with repmgr in Docker Swarm deployments, causing cascade failures in standby initialization and pgpool operation.

**Root Cause**: PostgreSQL was starting with `listen_addresses=localhost` during initialization, preventing repmgr from connecting via the Docker Swarm overlay network hostname.

**Files Modified**: `postgres/initdb.sh`
- Removed `listen_addresses=localhost` restriction from startup commands
- Fixed `PG_MASTER_NODE_NAME` to properly read from `PGMASTER` environment variable
- Added DNS resolution checks for Docker Swarm overlay network compatibility
- Added explicit return codes to `wait_for_master()` function

**Documentation**: See `DOCKER_SWARM_FIX.md` for comprehensive analysis and `QUICK_FIX_SUMMARY.md` for quick reference.

**Impact**: This fix resolves:
- Primary registration failures: `connection to server at "pg01" failed: Connection refused`
- Standby nodes waiting indefinitely for master registration
- Pgpool unable to identify primary node
- Repmgrd failing with: `no metadata record found for this node`

## Troubleshooting Tips

- **Containers restarting**: Check logs for initialization errors
- **Replication lag**: Check network connectivity and WAL archive
- **Pgpool connection issues**: Verify `pgpool_status` file and backend node availability
- **SSH failures**: Check SSH keys and port 222 accessibility
- **VIP not assigned**: Verify watchdog configuration and network interfaces
- **Repmgr registration failures in Swarm**: See `DOCKER_SWARM_FIX.md` - likely PostgreSQL listening configuration issue
- **DNS resolution issues**: Docker Swarm overlay networks may have brief DNS propagation delays

## Additional Resources

- **Main Documentation**: README.md
- **Deployment Guide**: DEPLOYMENT.md
- **Quick Start**: QUICKSTART.md
- **Docker Swarm Fix**: DOCKER_SWARM_FIX.md (comprehensive troubleshooting for Swarm issues)
- **Quick Fix Summary**: QUICK_FIX_SUMMARY.md (quick reference for common problems)
- **Repmgr Registration Fix**: REPMGR_REGISTRATION_FIX.md (detailed fix explanation)
- **SSH Fix Summary**: SSH_FIX_SUMMARY.md (SSH connection improvements)
- **Pgpool Watchdog**: doc/pgpoolwatchdog.md
- **Failover Details**: failover.md
- **Repmgr Auto-Failover**: doc/repmgr_auto.md (deprecated approach)

## Version Information

- **PostgreSQL**: 17.x
- **Pgpool-II**: 4.6.x
- **repmgr**: 5.5.x
- **Node.js**: Compatible with current LTS
- **React**: 16.x
- **Debian**: 12 (Bookworm)

Version is managed in `version.txt` and used throughout build and deployment scripts.
