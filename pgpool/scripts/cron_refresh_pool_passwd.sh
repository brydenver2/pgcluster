#!/bin/bash
# Cron wrapper for pool_passwd refresh
# This script can be run by cron to automatically refresh pool_passwd

# Source environment variables from entrypoint context if available
if [ -f /tmp/pgpool_env ]; then
  source /tmp/pgpool_env
fi

# Log to a file for cron runs
LOGFILE=/var/log/pgpool/pool_passwd_refresh.log
mkdir -p /var/log/pgpool

echo "=== Pool passwd refresh started at $(date) ===" >> ${LOGFILE}
/scripts/refresh_pool_passwd.sh >> ${LOGFILE} 2>&1
echo "=== Pool passwd refresh completed at $(date) ===" >> ${LOGFILE}
echo "" >> ${LOGFILE}
