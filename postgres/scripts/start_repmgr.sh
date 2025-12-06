#!/bin/bash
PGVER=${PGVER:-12}
if [ "$INITIAL_NODE_TYPE" == "single" -o "a${REPMGRD}" == "afalse" -o "a${REPMGRD}" == "ano" ] ; then
  echo "single node type is $INITIAL_NODE_TYPE or REPMGRD is ${REPMGRD}: do not start repmgr"
  exec tail -f /scripts/start_repmgr.sh
else
  echo "sleep 60 before starting repmgrd"
  sleep 60
  
  # Before starting repmgrd, check if this node is registered
  # This helps recover from failed initial registration
  NODE_ID=${NODE_ID:-1}
  REPMGRPWD=${REPMGRPWD:-rep123}
  export PGPASSFILE=/home/postgres/.pgpass
  
  NODE_REGISTERED=$(psql -h localhost -U repmgr -d repmgr -tAc "SELECT COUNT(*) FROM repmgr.nodes WHERE node_id=${NODE_ID}" 2>/dev/null)
  
  if [ "$NODE_REGISTERED" = "0" ] || [ -z "$NODE_REGISTERED" ] ; then
    echo "Node ${NODE_ID} not registered in repmgr metadata, attempting registration now"
    IS_IN_RECOVERY=$(psql -h localhost -tAc "SELECT pg_is_in_recovery()" 2>/dev/null)
    if [ "$IS_IN_RECOVERY" = "f" ] ; then
      echo "Registering as primary"
      /usr/lib/postgresql/${PGVER}/bin/repmgr -f /etc/repmgr/${PGVER}/repmgr.conf -v primary register --force
    else
      echo "Registering as standby"
      /usr/lib/postgresql/${PGVER}/bin/repmgr -f /etc/repmgr/${PGVER}/repmgr.conf -v standby register --force
    fi
  else
    echo "Node ${NODE_ID} already registered in repmgr metadata"
  fi
  
  exec /usr/lib/postgresql/${PGVER}/bin/repmgrd -f /etc/repmgr/${PGVER}/repmgr.conf --verbose --monitoring-history --daemonize=false
fi
