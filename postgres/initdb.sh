#!/bin/bash

echo "id is : `id -un`"
if [ `id -un` != "postgres" ] ; then
 echo "This script must be run by user postgres"
 exit 1
fi

log_info(){
 echo `date +"%Y-%m-%d %H:%M:%S.%s"` - INFO - $1 
}

function shutdown()
{
  echo "Shutting down PostgreSQL"
  pg_ctl stop
}

#
# return 1 when user exists in postgres, 0 otherwise
#
user_exists(){
 USER=${1}
 psql -c "select usename from pg_user where usename=upper('${USER}')" | grep -q "(0 rows)"
 if  [ $? -eq 0  ] ; then
   echo 0
 else
   echo 1
 fi
}

#
# create two users for the micro-service given as parameter 1, passwords are given as param 2 and 3
# if the users already exist, the password is changed
#
create_user(){
 MS=${1}
 MSOWNER=${1}_owner
 MSUSER=${1}_user
 MSOWNER_PWD=${2}
 MSUSER_PWD=${3}
 USREXISTS=$(user_exists ${MSOWNER} )
 if [ $USREXISTS -eq 0 ] ; then
  log_info "create ${MSOWNER} with password ${MSOWNER_PWD}"
  psql --dbname phoenix <<-EOF
   create user ${MSOWNER} with login password '${MSOWNER_PWD}';
   create schema ${MSOWNER} authorization ${MSOWNER};
   \q
EOF
 else
  log_info "user ${MSOWNER} already exists, set password to ${MSOWNER_PWD}"
  psql --dbname phoenix -c "alter user ${MSOWNER} with login password '{MSOWNER_PWD}';"
 fi
 USREXISTS=$( user_exists ${MSUSER} )
 if [ $USREXISTS -eq 0 ] ; then
  log_info "create ${MSUSER} with password ${MSUSER_PWD}"
  psql --dbname phoenix <<-EOF
    create user ${MSUSER} with login password '${MSUSER_PWD}';
    alter user ${MSUSER} set search_path to "\$user","${MSOWNER}", public;
    \q
EOF
  psql --username=${MSOWNER} --dbname phoenix <<-EOF
    grant usage on schema ${MSOWNER} to ${MSUSER};
    alter default privileges in schema ${MSOWNER} grant select,insert,update,delete on tables to ${MSUSER};
    alter default privileges in schema ${MSOWNER} grant usage,select on sequences to ${MSUSER};
    alter default privileges in schema ${MSOWNER} grant execute on functions to ${MSUSER};
    \q
EOF
 else
  log_info "user ${MSUSER} already exists, set password to ${MSUSER_PWD}"
  psql --dbname phoenix -c "alter user ${MSUSER} with login password '{MSUSER_PWD}'";
 fi
}

wait_for_master(){
 SLEEP_TIME=10
 HOST=${PG_MASTER_NODE_NAME}
 PORT=5432
 NBRTRY=24

 log_info "waiting for master on ${HOST} to be ready"
 
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
 
 # Verify .pgpass is readable
 if [ ! -f /home/postgres/.pgpass ] ; then
   log_info "ERROR: /home/postgres/.pgpass does not exist!"
 else
   log_info ".pgpass file exists with permissions: $(ls -la /home/postgres/.pgpass)"
 fi
 
 # Ensure PGPASSFILE is set
 export PGPASSFILE=/home/postgres/.pgpass
 
 nbrlines=0
 while [ $nbrlines -lt 1 -a $NBRTRY -gt 0 ] ; do
  echo "waiting for repmgr node to be initialized with the master (attempt $((25-NBRTRY))/24)"
  psql -U repmgr -h ${HOST} repmgr -t -c "select node_name,active from nodes;" > /tmp/nodes 2>&1
  psql_ret=$?
  if [ $psql_ret -ne 0 ] ; then
    log_info "cannot connect to $HOST in psql (exit code: $psql_ret)"
    cat /tmp/nodes
    nbrlines=0
  else
    nbrlines=$( grep -v "^$" /tmp/nodes | wc -l )
    log_info "Successfully queried repmgr.nodes, found $nbrlines nodes"
    if [ $nbrlines -gt 0 ] ; then
      log_info "Node list:"
      cat /tmp/nodes
    fi
  fi
  NBRTRY=$((NBRTRY-1))
  if [ $nbrlines -lt 1 ] ; then
    sleep $SLEEP_TIME
  fi
 done
 
 # Return success if we found at least one node, failure otherwise
 if [ $nbrlines -ge 1 ] ; then
   log_info "Master has $nbrlines nodes registered, proceeding with standby setup"
   return 0
 else
   log_info "Master has no nodes registered after waiting, cannot proceed"
   return 1
 fi
}

log_info "Start initdb on host `hostname`"
log_info "MSLIST: ${MSLIST}" 
log_info "MSOWNERPWDLIST: ${MSOWNERPWDLIST}" 
log_info "MSUSERPWDLIST: ${MSUSERPWDLIST}" 
log_info "PGDATA: ${PGDATA}" 
INITIAL_NODE_TYPE=${INITIAL_NODE_TYPE:-single} 
log_info "INITIAL_NODE_TYPE: ${INITIAL_NODE_TYPE}" 
export PATH=$PATH:/usr/lib/postgresql/${PGVER}/bin
MSLIST=${MSLIST-"keycloak,apiman,asset,ingest,playout"}
NODE_ID=${NODE_ID:-1}
NODE_NAME=${NODE_NAME:-"pg0${NODE_ID}"}
ARCHIVELOG=${ARCHIVELOG:-1}
PG_MASTER_NODE_NAME=${PGMASTER:-pg01}
log_info "NODE_ID: $NODE_ID"
log_info "NODE_NAME: $NODE_NAME"
log_info "ARCHIVELOG: $ARCHIVELOG"
log_info "PG_MASTER_NODE_NAME: $PG_MASTER_NODE_NAME"
log_info "docker: ${docker}"
# automatic or manual
REPMGRD_FAILOVER_MODE=${REPMGRD_FAILOVER_MODE:-manual}
log_info "REPMGRD_FAILOVER_MODE: ${REPMGRD_FAILOVER_MODE}"

create_microservices(){
 IFS=',' read -ra MSERVICES <<< "$MSLIST"
 IFS=',' read -ra MSOWNERPASSWORDS <<< "$MSOWNERPWDLIST"
 IFS=',' read -ra MSUSERPASSWORDS <<< "$MSUSERPWDLIST"
 for((i=0;i<${#MSERVICES[@]};i++))
 do
    if [ ! -z ${MSOWNERPASSWORDS[$i]} ] ; then
      OWNERPWD=${MSOWNERPASSWORDS[$i]}
    else
      OWNERPWD=${MSERVICES[$i]}"_owner"
    fi
    if [ ! -z ${MSUSERPASSWORDS[$i]} ] ; then
      USERPWD=${MSUSERPASSWORDS[$i]}
    else
      USERPWD=${MSERVICES[$i]}"_user"
    fi
    log_info "creating postgres users for microservice ${MSERVICES[$i]} with passwords ${OWNERPWD} and ${USERPWD}"
    create_user  ${MSERVICES[$i]} ${OWNERPWD} ${USERPWD}
 done
}

#
# Note that the code below is executed everytime a container is created
# this is needed in order to patch some files that are not persisted accross run
# i.e. files that are outside the PGDATA directory (PGDATA being on shared volume)
#
# Read repmgr password from file or environment
if [ ! -z ${REPMGRPWD_FILE} ] && [ -f ${REPMGRPWD_FILE} ] ; then
  REPMGRPWD=$(cat ${REPMGRPWD_FILE} | tr -d '\n\r' | xargs)
  log_info "repmgr password loaded from file: ${REPMGRPWD_FILE}"
  log_info "repmgr password length: ${#REPMGRPWD} characters"
  # Debug: show first/last chars (not full password for security)
  log_info "repmgr password debug: starts with '$(echo -n "${REPMGRPWD}" | head -c 3)', ends with '$(echo -n "${REPMGRPWD}" | tail -c 3)'"
elif [ ! -z ${REPMGRPWD} ] ; then
  log_info "repmgr password set via env"
else
  REPMGRPWD=rep123
  log_info "repmgr password default to rep123"
fi

# Read postgres superuser password from file or environment
if [ ! -z ${POSTGRES_PASSWORD_FILE} ] && [ -f ${POSTGRES_PASSWORD_FILE} ] ; then
  PG_SUPERUSER_PWD=$(cat ${POSTGRES_PASSWORD_FILE} | tr -d '\n\r' | xargs)
  log_info "postgres superuser password loaded from file: ${POSTGRES_PASSWORD_FILE}"
elif [ ! -z ${POSTGRES_PASSWORD} ] ; then
  log_info "postgres superuser password set via POSTGRES_PASSWORD env"
  PG_SUPERUSER_PWD=${POSTGRES_PASSWORD}
else
  log_info "postgres superuser password defaults to REPMGRPWD"
  PG_SUPERUSER_PWD=${REPMGRPWD}
fi

log_info "setup .pgpass for replication and for repmgr"
echo "*:*:repmgr:repmgr:${REPMGRPWD}" > /home/postgres/.pgpass
echo "*:*:replication:repmgr:${REPMGRPWD}" >> /home/postgres/.pgpass
chmod 600 /home/postgres/.pgpass

# patch script /scripts/repmgrd_event.sh 
sed -i -e "s/##REPMGRD_FAILOVER_MODE##/${REPMGRD_FAILOVER_MODE}/" /scripts/repmgrd_event.sh
#build repmgr.conf
sudo touch /etc/repmgr/${PGVER}/repmgr.conf && sudo chown postgres:postgres /etc/repmgr/${PGVER}/repmgr.conf
cat <<EOF > /etc/repmgr/${PGVER}/repmgr.conf
node_id=${NODE_ID}
node_name=${NODE_NAME}
conninfo='host=${NODE_NAME} dbname=repmgr user=repmgr password=${REPMGRPWD} connect_timeout=2'
data_directory='/data'
use_replication_slots=1
restore_command = 'test -f /archive/%f && cp /archive/%f %p || exit 0'

#log_file='/var/log/repmgr/repmgr.log'
log_facility=STDERR
failover=${REPMGRD_FAILOVER_MODE}
reconnect_attempts=${REPMGRD_RECONNECT_ATTEMPS:-6}
reconnect_interval=${REPMGRD_INTERVAL:-5}
event_notification_command='/scripts/repmgrd_event.sh %n "%e" %s "%t" "%d" %p %c %a'
monitor_interval_secs=5

pg_bindir='/usr/lib/postgresql/${PGVER}/bin'

service_start_command = 'sudo /usr/local/bin/supervisorctl start postgres'
service_stop_command = 'sudo /usr/local/bin/supervisorctl stop postgres'
service_restart_command = 'sudo /usr/local/bin/supervisorctl restart postgres'
service_reload_command = 'pg_ctl reload'

promote_command='repmgr -f /etc/repmgr/${PGVER}/repmgr.conf standby promote'
follow_command='repmgr -f /etc/repmgr/${PGVER}/repmgr.conf standby follow -W --upstream-node-id=%n'

EOF
#
# stuff below will be done only once, when the database has not been initialized
#
#
if [ ! -f ${PGDATA}/postgresql.conf ] ; then
  log_info "$PGDATA/postgresql.conf does not exist"
  if [[ "a$INITIAL_NODE_TYPE" != "aslave" ]] ; then
    log_info "This node is the master or we are in a single db setup, let us init the db"
    pg_ctl initdb -D ${PGDATA} -o "--encoding='UTF8' --locale='en_US.UTF8'"
    log_info "Adding include_dir in $PGDATA/postgresql.conf"
    mkdir $PGDATA/conf.d
    cp /opt/pgconfig/01custom.conf $PGDATA/conf.d
    echo "include_dir = './conf.d'" >> $PGDATA/postgresql.conf
    cat <<-EOF >> $PGDATA/pg_hba.conf
# replication manager
local  replication   repmgr                      trust
host   replication   repmgr      127.0.0.1/32    trust
host   replication   repmgr      0.0.0.0/0       md5
local   repmgr        repmgr                     trust
host    repmgr        repmgr      127.0.0.1/32   trust
host    repmgr        repmgr      0.0.0.0/0      md5
EOF
    echo "host     all           all        0.0.0.0/0            md5" >> $PGDATA/pg_hba.conf
    echo starting database
    ps -ef
    # Start PostgreSQL listening on all addresses to allow repmgr registration to work
    pg_ctl -D ${PGDATA} start -w 
    psql --command "create database phoenix ENCODING='UTF8' LC_COLLATE='en_US.UTF8';"
    create_microservices
    psql phoenix -c "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\"";
    log_info "Creating repmgr database and user"
    # NB: super user needed for replication
    psql <<-EOF
     create user repmgr with superuser login password '${REPMGRPWD}' ;
     alter user repmgr set search_path to repmgr,"\$user",public;
     \q
EOF
    log_info "set password for postgres to: ${PG_SUPERUSER_PWD}"
    psql --command "alter user postgres with login password '${PG_SUPERUSER_PWD}';"
    psql --command "create database repmgr with owner=repmgr ENCODING='UTF8' LC_COLLATE='en_US.UTF8';"
    log_info "Installing repmgr extension in repmgr database"
    psql -d repmgr -c "CREATE EXTENSION IF NOT EXISTS repmgr;"
    if [ -f /usr/share/postgresql/${PGVER}/extension/pgpool-recovery.sql ] ; then
      log_info "pgpool extensions"
      psql -c "create extension pgpool_recovery;" -d template1
      psql -c "create extension pgpool_adm;"
    else
      log_info "pgpool-recovery.sql extension not found"
    fi
    cp /scripts/pgpool/pgpool_recovery.sh /scripts/pgpool/pgpool_remote_start ${PGDATA}/
    chmod 700 ${PGDATA}/pgpool_remote_start ${PGDATA}/pgpool_recovery.sh
    log_info "Create hcuser"
    psql -c "create user hcuser with login password 'hcuser';"
    echo "ARCHIVELOG=$ARCHIVELOG" > $PGDATA/override.env
    echo "Start postgres again to register master"
    pg_ctl stop
    pg_ctl start -w
    log_info "Register master in repmgr"
    repmgr -f /etc/repmgr/${PGVER}/repmgr.conf -v master register
    pg_ctl stop
  else
    log_info "This is a slave. Wait that master is up and running"
    wait_for_master
    if [ $? -eq 0 ] ; then
     log_info "Master ready, sleep 10 seconds before cloning slave"
     sleep 10
     sudo rm -rf ${PGDATA}/*
     repmgr -h ${PG_MASTER_NODE_NAME} -U repmgr -d repmgr -D ${PGDATA} -f /etc/repmgr/${PGVER}/repmgr.conf standby clone
     pg_ctl -D ${PGDATA} start -w
     log_info "Standby started, waiting 5 seconds for replication to stabilize"
     sleep 5
     log_info "Registering standby with repmgr (using --force to handle catchup state)"
     repmgr -f /etc/repmgr/${PGVER}/repmgr.conf standby register --force
     if [ $? -ne 0 ] ; then
       log_info "WARNING: Standby registration failed, but continuing"
     else
       log_info "Standby registration successful"
     fi
     pg_ctl stop
    else
     log_info "Master is not ready, standby will not be initialized"
    fi
  fi
else
  log_info "File ${PGDATA}/postgresql.conf already exist"
  # Ensure repmgr extension is installed even on restart
  log_info "Checking if repmgr database and extension need to be set up"
  # Start postgres temporarily to check/install extension - listen on all addresses for repmgr
  pg_ctl -D ${PGDATA} start -w
  
  # Check if this is a standby node (read-only)
  IS_IN_RECOVERY=$(psql -tAc "SELECT pg_is_in_recovery()")
  
  if [ "$IS_IN_RECOVERY" = "t" ] ; then
    log_info "This node is a standby (read-only), skipping password updates"
    log_info "Password will be replicated from primary node"
  else
    log_info "This node is primary, updating passwords"
    
    # Check if repmgr user exists, create if not
    psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='repmgr'" | grep -q 1
    if [ $? -ne 0 ] ; then
      log_info "Creating repmgr user"
      psql <<-EOF
       create user repmgr with superuser login password '${REPMGRPWD}' ;
       alter user repmgr set search_path to repmgr,"\$user",public;
       \q
EOF
    else
      log_info "repmgr user already exists, updating password"
      log_info "Updating repmgr password (length: ${#REPMGRPWD})"
      psql -c "alter user repmgr with superuser login password '${REPMGRPWD}';"
      if [ $? -eq 0 ] ; then
        log_info "repmgr password updated successfully"
      else
        log_info "ERROR: Failed to update repmgr password"
      fi
    fi
    
    # Also update postgres superuser password on every restart
    log_info "Updating postgres superuser password"
    psql -c "alter user postgres with login password '${PG_SUPERUSER_PWD}';"
    if [ $? -eq 0 ] ; then
      log_info "postgres superuser password updated successfully"
    else
      log_info "ERROR: Failed to update postgres password"
    fi
  fi
  
  # Test TCP/IP connection with updated password (not unix socket)
  log_info "Testing TCP/IP repmgr authentication with updated password"
  PGPASSWORD="${REPMGRPWD}" psql -h 127.0.0.1 -U repmgr -d repmgr -c "SELECT 1;" > /tmp/auth_test.log 2>&1
  if [ $? -eq 0 ] ; then
    log_info "SUCCESS: repmgr TCP/IP authentication test passed"
  else
    log_info "ERROR: repmgr TCP/IP authentication test failed:"
    cat /tmp/auth_test.log | while read line; do log_info "  $line"; done
  fi
  
  # Also test replication connection
  log_info "Testing replication connection with updated password"
  PGPASSWORD="${REPMGRPWD}" psql -h 127.0.0.1 -U repmgr -d replication=yes -c "IDENTIFY_SYSTEM;" > /tmp/repl_test.log 2>&1
  if [ $? -eq 0 ] ; then
    log_info "SUCCESS: replication authentication test passed"
  else
    log_info "ERROR: replication authentication test failed:"
    cat /tmp/repl_test.log | while read line; do log_info "  $line"; done
  fi
  
  # Check if repmgr database exists, create if not
  psql -lqt | cut -d \| -f 1 | grep -qw repmgr
  if [ $? -ne 0 ] ; then
    log_info "Creating repmgr database"
    psql --command "create database repmgr with owner=repmgr ENCODING='UTF8' LC_COLLATE='en_US.UTF8';"
  else
    log_info "repmgr database already exists"
  fi
  
  # Check if repmgr extension exists, create if not
  psql -d repmgr -tAc "SELECT 1 FROM pg_extension WHERE extname='repmgr'" | grep -q 1
  if [ $? -ne 0 ] ; then
    log_info "Installing repmgr extension in repmgr database"
    psql -d repmgr -c "CREATE EXTENSION IF NOT EXISTS repmgr;"
  else
    log_info "repmgr extension already installed"
  fi
  
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
      log_info "This node is a standby, checking if primary is accessible before registering"
      # Wait for the primary to be ready (max 2 minutes)
      PRIMARY_READY=0
      for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
        log_info "Checking connectivity to primary ${PG_MASTER_NODE_NAME} (attempt $i/12)"
        # Use timeout command to force kill psql if it hangs (10 seconds timeout)
        timeout 10 psql -h ${PG_MASTER_NODE_NAME} -U repmgr -d repmgr -tAc "SELECT 1" > /tmp/psql_test.out 2>&1
        RESULT=$?
        log_info "Connection attempt result: $RESULT"
        if [ $RESULT -eq 0 ] ; then
          log_info "Primary ${PG_MASTER_NODE_NAME} is accessible"
          # Additional check: verify primary has repmgr metadata initialized
          NODE_COUNT=$(timeout 10 psql -h ${PG_MASTER_NODE_NAME} -U repmgr -d repmgr -tAc "SELECT COUNT(*) FROM repmgr.nodes" 2>/dev/null)
          if [ $? -eq 0 ] && [ "$NODE_COUNT" -ge 1 ] ; then
            log_info "Primary has $NODE_COUNT nodes registered, ready to proceed"
            PRIMARY_READY=1
            break
          else
            log_info "Primary is up but repmgr metadata not ready yet, waiting..."
          fi
        elif [ $RESULT -eq 124 ] ; then
          log_info "Connection attempt timed out after 10 seconds"
        else
          log_info "Primary not ready yet (error code $RESULT), waiting 10 seconds..."
        fi
        sleep 10
      done
      
      if [ $PRIMARY_READY -eq 1 ] ; then
        log_info "Registering standby with repmgr"
        repmgr -f /etc/repmgr/${PGVER}/repmgr.conf -v standby register --force
        if [ $? -ne 0 ] ; then
          log_info "WARNING: Failed to register node as standby"
        else
          log_info "Standby registration successful"
        fi
      else
        log_info "WARNING: Primary not accessible after 2 minutes, skipping registration"
        log_info "Node will attempt to register when repmgrd starts"
      fi
    fi
  else
    log_info "Node already registered in repmgr metadata"
  fi
  
  # Stop postgres before starting in foreground
  pg_ctl stop -w
fi
#TODO: this trap is not used
trap shutdown HUP INT QUIT ABRT KILL ALRM TERM TSTP
ps -ef
log_info "start postgres in foreground"
exec postgres -D ${PGDATA} 
