# Fix for SSH Connection Failures (Exit Status 255)

## Problem
Your logs showed two processes exiting with status 255:
```
2025-12-05 05:01:45,091 INFO reaped unknown pid 80 (exit status 255)
2025-12-05 05:01:45,091 INFO reaped unknown pid 89 (exit status 255)
```

Exit status 255 typically means SSH connection failures.

## Root Cause
The pgpool recovery scripts (`pgpool_remote_start` and `pgpool_recovery.sh`) were attempting SSH connections to other cluster nodes without:
- Checking if the target host is reachable first
- Setting connection timeouts
- Implementing retry logic
- Proper error handling

This caused orphaned SSH processes to fail and be "reaped" by supervisord.

## What Was Fixed

### 1. pgpool_remote_start
**Before:** Backgrounded SSH command without error handling
```bash
$ssh_options "/scripts/pg_start.sh" &
sleep 20
$ssh_options "supervisorctl status all"
```

**After:** Added connectivity checks and removed dangerous backgrounding
- Pre-flight SSH connectivity check with 3 retries
- Removed `&` to prevent orphaned processes
- Added ConnectTimeout to all SSH commands
- Proper error logging

### 2. pgpool_recovery.sh
**Before:** Direct SSH commands with no error handling
```bash
$ssh_copy "/scripts/pg_stop.sh"
$ssh_copy "rm -Rf $replica_path/* ${ARCHIVE_DIR}/*"
...
```

**After:** Added robust error handling
- Pre-flight SSH connectivity check with 3 retries
- `ssh_exec()` wrapper with retry logic for all operations
- Timeout settings on all SSH commands
- **BONUS:** Fixed typo `supervisor` → `supervisorctl` (this was a pre-existing bug!)

## Benefits
✅ SSH failures handled gracefully with automatic retries
✅ Clear error messages for debugging
✅ No more orphaned SSH processes
✅ No more "reaped unknown pid" messages with exit 255
✅ More reliable cluster recovery operations

## Testing
After rebuilding your images with these changes, you should no longer see the exit status 255 errors. 

To test:
1. Rebuild images: `./build.sh`
2. Start your cluster: `docker-compose up -d`
3. Check logs: `docker-compose logs -f pg01`
4. You should see clean startup without the "reaped unknown pid" errors

## What to Watch For
The improved logging will show:
- "Checking SSH connectivity to X (attempt Y/Z)" - when checking connectivity
- "SSH connection to X successful" - when connection works
- "SSH connection to X failed" - if it fails (with retry info)
- "ERROR: Failed to establish SSH connection..." - if all retries fail

This makes it much easier to diagnose cluster issues!

## Notes
- These scripts are only called by pgpool during recovery operations or when starting remote nodes
- In a single-node setup, these scripts may not be called at all
- The exit 255 errors were likely caused by pgpool trying to connect to nodes that weren't ready yet
- With the new retry logic, transient failures will be handled automatically
