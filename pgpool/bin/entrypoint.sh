#!/bin/bash

CONFIG_DIR=/etc/pgpool-II-10
CONFIG_FILE=${CONFIG_DIR}/pgpool.conf

wait_for_db(){
  SLEEP_TIME=5
  MAX_TRIES=60
  IFS=',' read -ra PG_HOSTS <<< "$1"
  while [ 0 -eq 0 ] ; do
    echo "Using list of backend $1 to find a db to connect to"
    i=0
    while [ $i -lt ${#PG_HOSTS[@]} ] ; do
      echo trying with ${PG_HOSTS[$i]}
      DBHOST=$( echo ${PG_HOSTS[$i]} | cut -f2 -d":" )
      port=$( echo ${PG_HOSTS[$i]} | cut -f3 -d":" )
      if [ -z $port ] ; then
        port=5432
      fi
      echo trying to connect to $DBHOST via ssh
      ssh -oPasswordAuthentication=no ${DBHOST} uname
      if [ $? -ne 0 ] ; then
        echo Cannot ssh to $DBHOST
        i=$((i+1))
      else
        echo Try psql connection on host $DBHOST
        # we could use pg_is_ready also
        ssh -oPasswordAuthentication=no $DBHOST "psql --username=repmgr -p ${port} repmgr -c \"select 1;\""
        ret=$?
        if [ $ret -eq 0 ] ; then
          echo "server ${DBHOST} ready"
          echo "pg backend found at host $DBHOST and port $port"
          return 0
        else
          echo "Cannot connect to ${DBHOST} in psql, pg not ready ?"
          i=$((i+1))
        fi
      fi
    done
    sleep $SLEEP_TIME
  done
}

PG_MASTER_NODE_NAME=${PG_MASTER_NODE_NAME:-pg01}
echo PG_MASTER_NODE_NAME=${PG_MASTER_NODE_NAME}
PG_BACKEND_NODE_LIST=${PG_BACKEND_NODE_LIST:-0:${PG_MASTER_NODE_NAME}:5432}
echo PG_BACKEND_NODE_LIST=${PG_BACKEND_NODE_LIST}
PGP_NODE_NAME=${PGP_NODE_NAME:-pgpool01}
echo PGP_NODE_NAME=${PGP_NODE_NAME}
REPMGRPWD=${REPMGRPWD:-rep123}
echo REPMGRPWD=${REPMGRPWD}
FAIL_OVER_ON_BACKEND_ERROR=${FAIL_OVER_ON_BACKEND_ERROR:-off}
echo FAIL_OVER_ON_BACKEND_ERROR=${FAIL_OVER_ON_BACKEND_ERROR}
CONNECTION_CACHE=${CONNECTION_CACHE:-on}
echo CONNECTION_CACHE=${CONNECTION_CACHE}

IFS=',' read -ra PG_HOSTS <<< "$PG_BACKEND_NODE_LIST"
nbrbackend=${#PG_HOSTS[@]}
if [ $nbrbackend -gt 1 ] ; then
  MASTER_SLAVE_MODE=on
else
  MASTER_SLAVE_MODE=off
fi
echo MASTER_SLAVE_MODE=$MASTER_SLAVE_MODE


echo "Waiting for one database to be ready"
wait_for_db $PG_BACKEND_NODE_LIST
echo "Checking backend databases state in repl_nodes table"
# if the cluster is initializing it is possible that repl_nodes does not contain
# all backend yet and so we might need to wait a bit...
ssh ${DBHOST} "psql -U repmgr repmgr -t -c 'select name,active from repl_nodes;'" > /tmp/repl_nodes
if [ $? -ne 0 ] ; then
  echo "error connecting to $DBHOST, this likely indicates an unexpected issue"
fi
nbrlines=$( grep -v "^$" /tmp/repl_nodes | wc -l )
NBRTRY=30
while [ $nbrlines -lt $nbrbackend -a $NBRTRY -gt 0 ] ; do
  echo "waiting for repl_nodes to be initialized: currently $nbrlines in repl_node, there must be one line per back-end ($nbrbackend)"
  ssh ${DBHOST} "psql -U repmgr repmgr -t -c 'select name,active from repl_nodes;'" > /tmp/repl_nodes
  nbrlines=$( grep -v "^$" /tmp/repl_nodes | wc -l )
  NBRTRY=$((NBRTRY-1))
  echo "Sleep 10 seconds, still $NBRTRY to go..."
  sleep 10
done
echo ">>>repl_nodes:"
cat /tmp/repl_nodes
> /tmp/pgpool_status
for i in ${PG_HOSTS[@]}
do
  h=$( echo $i | cut -f2 -d":" )
  echo "check state of $h in repl_nodes"
  active=$( grep $h /tmp/repl_nodes | sed -e "s/ //g" | cut -f2 -d"|" )
  echo "active is $active for $h"
  if [ "a$active" == "at" ] ; then
    echo $h is up in repl_nodes
    echo up >> /tmp/pgpool_status
  fi
  if [ "a$active" == "af" ] ; then
    echo $h is down in repl_nodes
    echo down >> /tmp/pgpool_status
  fi
  if [ "a$active" == "a" ] ; then
    (>&2 echo "backend $h is not found in repl_nodes, marking as up")
    echo up >> /tmp/pgpool_status
  fi
done
echo ">>> pgpool_status file"
cat /tmp/pgpool_status
echo "Create user hcuser (fails if the hcuser already exists, which is ok)"
ssh ${DBHOST} "psql -c \"create user hcuser with login password 'hcuser';\""
echo "Generate pool_passwd file from ${DBHOST}"
touch ${CONFIG_DIR}/pool_passwd
ssh postgres@${DBHOST} "psql -c \"select rolname,rolpassword from pg_authid;\"" | awk 'BEGIN {FS="|"}{print $1" "$2}' | grep md5 | while read f1 f2
do
 # delete the line and recreate it
 echo "setting passwd of $f1 in ${CONFIG_DIR}/pool_passwd"
 sed -i -e "/^${f1}:/d" ${CONFIG_DIR}/pool_passwd
 echo $f1:$f2 >> ${CONFIG_DIR}/pool_passwd
done
echo "Builing the configuration in $CONFIG_FILE"

cat <<EOF > $CONFIG_FILE
# config file generated by entrypoint at `date`
listen_addresses = '*'
port = 9999
socket_dir = '/var/run/postgresql'
pcp_listen_addresses = '*'
pcp_port = 9898
pcp_socket_dir = '/var/run/pgpool'
listen_backlog_multiplier = 2
serialize_accept = off
EOF
echo "Adding backend-connection info for each pg node in $PG_BACKEND_NODE_LIST"
IFS=',' read -ra HOSTS <<< "$PG_BACKEND_NODE_LIST"
for HOST in ${HOSTS[@]}
do
    IFS=':' read -ra INFO <<< "$HOST"

    NUM=""
    HOST=""
    PORT="9999"
    WEIGHT=1
    DIR="/u01/pg96/data"
    FLAG="ALLOW_TO_FAILOVER"

    [[ "${INFO[0]}" != "" ]] && NUM="${INFO[0]}"
    [[ "${INFO[1]}" != "" ]] && HOST="${INFO[1]}"
    [[ "${INFO[2]}" != "" ]] && PORT="${INFO[2]}"
    [[ "${INFO[3]}" != "" ]] && WEIGHT="${INFO[3]}"
    [[ "${INFO[4]}" != "" ]] && DIR="${INFO[4]}"
    [[ "${INFO[5]}" != "" ]] && FLAG="${INFO[5]}"

    echo "
backend_hostname$NUM = '$HOST'
backend_port$NUM = $PORT
backend_weight$NUM = $WEIGHT
backend_data_directory$NUM = '$DIR'
backend_flag$NUM = '$FLAG'
" >>  $CONFIG_FILE
done
cat <<EOF >> $CONFIG_FILE
# - Authentication -
enable_pool_hba = on
pool_passwd = 'pool_passwd'
authentication_timeout = 60
ssl = off
#------------------------------------------------------------------------------
# POOLS
#------------------------------------------------------------------------------
# - Concurrent session and pool size -
num_init_children = ${NUM_INIT_CHILDREN:-62}
                                   # Number of concurrent sessions allowed
                                   # (change requires restart)
max_pool = ${MAX_POOL:-4}
                                   # Number of connection pool caches per connection
                                   # (change requires restart)
# - Life time -
child_life_time = 300
                                   # Pool exits after being idle for this many seconds
child_max_connections = 0
                                   # Pool exits after receiving that many connections
                                   # 0 means no exit
connection_life_time = 0
                                   # Connection to backend closes after being idle for this many seconds
                                   # 0 means no close
client_idle_limit = 0
                                   # Client is disconnected after being idle for that many seconds
                                   # (even inside an explicit transactions!)
                                   # 0 means no disconnection
#------------------------------------------------------------------------------
# LOGS
#------------------------------------------------------------------------------

# - Where to log -

log_destination = 'stderr'
                                   # Where to log
                                   # Valid values are combinations of stderr,
                                   # and syslog. Default to stderr.

# - What to log -

log_line_prefix = '%t: pid %p: '   # printf-style string to output at beginning of each log line.

log_connections = on
                                   # Log connections
log_hostname = on
                                   # Hostname will be shown in ps status
                                   # and in logs if connections are logged
log_statement = ${LOG_STATEMENT:-off}
                                   # Log all statements
log_per_node_statement = off
                                   # Log all statements
                                   # with node and backend informations
log_standby_delay = 'if_over_threshold'
                                   # Log standby delay
                                   # Valid values are combinations of always,
                                   # if_over_threshold, none

# - syslog specific -

syslog_facility = 'LOCAL0'
                                   # Syslog local facility. Default to LOCAL0
syslog_ident = 'pgpool'
                                   # Syslog program identification string
                                   # Default to 'pgpool'
debug_level = ${DEBUG_LEVEL:-0}
                                   # Debug message verbosity level
                                   # 0 means no message, 1 or more mean verbose
log_error_verbosity = verbose          # terse, default, or verbose messages
#------------------------------------------------------------------------------
# FILE LOCATIONS
#------------------------------------------------------------------------------

pid_file_name = '/var/run/pgpool/pgpool.pid'
                                   # PID file name
                                   # (change requires restart)
logdir = '/tmp'
                                   # Directory of pgPool status file
                                   # (change requires restart)
#------------------------------------------------------------------------------
# CONNECTION POOLING
#------------------------------------------------------------------------------

connection_cache = ${CONNECTION_CACHE}
                                   # Activate connection pools
                                   # (change requires restart)

                                   # Semicolon separated list of queries
                                   # to be issued at the end of a session
                                   # The default is for 8.3 and later
reset_query_list = 'ABORT; DISCARD ALL'
                                   # The following one is for 8.2 and before
#reset_query_list = 'ABORT; RESET ALL; SET SESSION AUTHORIZATION DEFAULT'
#------------------------------------------------------------------------------
# REPLICATION MODE
#------------------------------------------------------------------------------
replication_mode = off
#------------------------------------------------------------------------------
# LOAD BALANCING MODE
#------------------------------------------------------------------------------

load_balance_mode = ${MASTER_SLAVE_MODE}
                                   # Activate load balancing mode
                                   # (change requires restart)
ignore_leading_white_space = on
                                   # Ignore leading white spaces of each query
white_function_list = ''
                                   # Comma separated list of function names
                                   # that don't write to database
                                   # Regexp are accepted
black_function_list = 'currval,lastval,nextval,setval'
                                   # Comma separated list of function names
                                   # that write to database
                                   # Regexp are accepted

database_redirect_preference_list = ''
                                                                   # comma separated list of pairs of database and node id.
                                                                   # example: postgres:primary,mydb[0-4]:1,mydb[5-9]:2'
                                                                   # valid for streaming replicaton mode only.

app_name_redirect_preference_list = ''
                                                                   # comma separated list of pairs of app name and node id.
                                                                   # example: 'psql:primary,myapp[0-4]:1,myapp[5-9]:standby'
                                                                   # valid for streaming replicaton mode only.
allow_sql_comments = off
                                                                   # if on, ignore SQL comments when judging if load balance or
                                                                   # query cache is possible.
                                                                   # If off, SQL comments effectively prevent the judgment
                                                                   # (pre 3.4 behavior).
#------------------------------------------------------------------------------
# MASTER/SLAVE MODE
#------------------------------------------------------------------------------

master_slave_mode = ${MASTER_SLAVE_MODE}
                                   # Activate master/slave mode
                                   # (change requires restart)
master_slave_sub_mode = 'stream'
                                   # Master/slave sub mode
                                   # Valid values are combinations slony or
                                   # stream. Default is slony.
                                   # (change requires restart)

# - Streaming -

sr_check_period = 10
                                   # Streaming replication check period
                                   # Disabled (0) by default
sr_check_user = 'repmgr'
                                   # Streaming replication check user
                                   # This is neccessary even if you disable streaming
                                   # replication delay check by sr_check_period = 0
sr_check_password = '${REPMGRPWD}'
                                   # Password for streaming replication check user
sr_check_database = 'repmgr'
                                   # Database name for streaming replication check
delay_threshold = 10000000
                                   # Threshold before not dispatching query to standby node
                                   # Unit is in bytes
                                   # Disabled (0) by default

# - Special commands -

follow_master_command = '/opt/scripts/follow_master.sh %d %h %m %p %H %M %P'
                                   # Executes this command after master failover
                                   # Special values:
                                   #   %d = node id
                                   #   %h = host name
                                   #   %p = port number
                                   #   %D = database cluster path
                                   #   %m = new master node id
                                   #   %H = hostname of the new master node
                                   #   %M = old master node id
                                   #   %P = old primary node id
                                                                   #   %r = new master port number
                                                                   #   %R = new master database cluster path
                                   #   %% = '%' character

#------------------------------------------------------------------------------
# HEALTH CHECK
#------------------------------------------------------------------------------

health_check_period = 40
                                   # Health check period
                                   # Disabled (0) by default
health_check_timeout = 10
                                   # Health check timeout
                                   # 0 means no timeout
health_check_user = 'hcuser'
                                   # Health check user
health_check_password = 'hcuser'
                                   # Password for health check user
health_check_database = 'postgres'
                                   # Database name for health check. If '', tries 'postgres' frist,
health_check_max_retries = 3
                                   # Maximum number of times to retry a failed health check before giving up.
health_check_retry_delay = 1
                                   # Amount of time to wait (in seconds) between retries.
connect_timeout = 10000
                                   # Timeout value in milliseconds before giving up to connect to backend.
                                                                   # Default is 10000 ms (10 second). Flaky network user may want to increase
                                                                   # the value. 0 means no timeout.
                                                                   # Note that this value is not only used for health check,
                                                                   # but also for ordinary conection to backend.
#------------------------------------------------------------------------------
# FAILOVER AND FAILBACK
#------------------------------------------------------------------------------
EOF
if [ $MASTER_SLAVE_MODE == "on" ] ; then
  cat <<EOF >> $CONFIG_FILE
failover_command = '/opt/scripts/failover.sh  %d %h %P %m %H %R'
                                   # Executes this command at failover
                                   # Special values:
                                   #   %d = node id
                                   #   %h = host name
                                   #   %p = port number
                                   #   %D = database cluster path
                                   #   %m = new master node id
                                   #   %H = hostname of the new master node
                                   #   %M = old master node id
                                   #   %P = old primary node id
                                                                   #   %r = new master port number
                                                                   #   %R = new master database cluster path
                                   #   %% = '%' character
failback_command = 'echo failback %d %h %p %D %m %H %M %P'
                                   # Executes this command at failback.
                                   # Special values:
                                   #   %d = node id
                                   #   %h = host name
                                   #   %p = port number
                                   #   %D = database cluster path
                                   #   %m = new master node id
                                   #   %H = hostname of the new master node
                                   #   %M = old master node id
                                   #   %P = old primary node id
                                                                   #   %r = new master port number
                                                                   #   %R = new master database cluster path
                                   #   %% = '%' character
EOF
else 
  cat <<EOF >> $CONFIG_FILE
failover_command = ''
failback_command = '' 
EOF
fi

cat <<EOF >> $CONFIG_FILE
fail_over_on_backend_error = ${FAIL_OVER_ON_BACKEND_ERROR}
                                   # Initiates failover when reading/writing to the
                                   # backend communication socket fails
                                   # If set to off, pgpool will report an
                                   # error and disconnect the session.

search_primary_node_timeout = 300
                                   # Timeout in seconds to search for the
                                   # primary node when a failover occurs.
                                   # 0 means no timeout, keep searching
                                   # for a primary node forever.

#------------------------------------------------------------------------------
# ONLINE RECOVERY
#------------------------------------------------------------------------------

recovery_user = 'postgres'
                                   # Online recovery user
recovery_password = '${REPMGRPWD}'
                                   # Online recovery password
recovery_1st_stage_command = 'pgpool_recovery.sh'
                                   # Executes a command in first stage
recovery_2nd_stage_command = 'echo recovery_2nd_stage_command'
                                   # Executes a command in second stage
recovery_timeout = 90
                                   # Timeout in seconds to wait for the
                                   # recovering node's postmaster to start up
                                   # 0 means no wait
client_idle_limit_in_recovery = 0
                                   # Client is disconnected after being idle
                                   # for that many seconds in the second stage
                                   # of online recovery
                                   # 0 means no disconnection
                                   # -1 means immediate disconnection
#------------------------------------------------------------------------------
# WATCHDOG
#------------------------------------------------------------------------------

# - Enabling -
EOF
if [ ! -z $DELEGATE_IP ] ; then
 echo "watchdog set to on because DELETEGATE_IP is set to $DELEGATE_IP"
 echo "use_watchdog = on" >> $CONFIG_FILE
else
 echo "watchdog set to off because DELEGATE_IP is not set"
 echo "use_watchdog = off" >> $CONFIG_FILE
fi
if [ ! -z ${TRUSTED_SERVERS} ] ; then
  cat <<EOF >> $CONFIG_FILE
# -Connection to up stream servers -
trusted_servers = '${TRUSTED_SERVERS}'
                                    # trusted server list which are used
                                    # to confirm network connection
                                    # (hostA,hostB,hostC,...)
                                    # (change requires restart)
EOF
fi
cat <<EOF >> $CONFIG_FILE
ping_path = '/bin'
                                    # ping command path
                                    # (change requires restart)

# - Watchdog communication Settings -
EOF
echo "wd_hostname = '${PGP_NODE_NAME}'" >> $CONFIG_FILE
cat <<EOF >> $CONFIG_FILE
                                    # Host name or IP address of this watchdog
                                    # (change requires restart)
wd_port = 9000
                                    # port number for watchdog service
                                    # (change requires restart)
wd_priority = 1
                                                                        # priority of this watchdog in leader election
                                                                        # (change requires restart)

wd_authkey = ''
                                    # Authentication key for watchdog communication
                                    # (change requires restart)

wd_ipc_socket_dir = '/var/run/pgpool'
                                                                        # Unix domain socket path for watchdog IPC socket
                                                                        # The Debian package defaults to
                                                                        # /var/run/postgresql
                                                                        # (change requires restart)
EOF
if [ ! -z ${DELEGATE_IP} ] ; then
  cat <<EOF >> $CONFIG_FILE
# - Virtual IP control Setting -

delegate_IP = '${DELEGATE_IP}'
                                    # delegate IP address
                                    # If this is empty, virtual IP never bring up.
                                    # (change requires restart)
if_cmd_path = '/opt/scripts'
                                    # path to the directory where if_up/down_cmd exists
                                    # (change requires restart)
if_up_cmd = 'ip_w.sh addr add $_IP_$/16 dev eth0 label eth0:0'
                                    # startup delegate IP command
                                    # (change requires restart)
if_down_cmd = 'ip_w.sh addr del $_IP_$/16 dev eth0'
                                    # shutdown delegate IP command
                                    # (change requires restart)
arping_path = '/opt/scripts'
                                    # arping command path
                                    # (change requires restart)
arping_cmd = 'arping_w.sh -U $_IP_$ -I eth0 -w 1'
                                    # arping command
                                    # (change requires restart)

# - Behaivor on escalation Setting -

clear_memqcache_on_escalation = on
                                    # Clear all the query cache on shared memory
                                    # when standby pgpool escalate to active pgpool
                                    # (= virtual IP holder).
                                    # This should be off if client connects to pgpool
                                    # not using virtual IP.
                                    # (change requires restart)
wd_escalation_command = ''
                                    # Executes this command at escalation on new active pgpool.
                                    # (change requires restart)
wd_de_escalation_command = ''
                                                                        # Executes this command when master pgpool resigns from being master.
                                                                        # (change requires restart)
EOF
fi
echo "heartbeat set-up"
IFS=',' read -ra HBEATS <<< "$PGP_HEARTBEATS"
for HBEAT in ${HBEATS[@]}
do
    IFS=':' read -ra INFO <<< "$HBEAT"

    NUM=""
    HOST=""
    HB_PORT="9694"
    HB_DEV=""

    [[ "${INFO[0]}" != "" ]] && NUM="${INFO[0]}"
    [[ "${INFO[1]}" != "" ]] && HOST="${INFO[1]}"
    [[ "${INFO[2]}" != "" ]] && HB_PORT="${INFO[2]}"

    echo "
heartbeat_destination$NUM = '$HOST'
heartbeat_destination_port$NUM = $HB_PORT
" >> $CONFIG_FILE
done
echo "Adding other pgpools in config"
IFS=',' read -ra OTHERS <<< "$PGP_OTHERS"
for OTHER in ${OTHERS[@]}
do
    IFS=':' read -ra INFO <<< "$OTHER"

    NUM=""
    HOST=""
    PGP_PORT="9999"
    WD_PORT=9000

    [[ "${INFO[0]}" != "" ]] && NUM="${INFO[0]}"
    [[ "${INFO[1]}" != "" ]] && HOST="${INFO[1]}"
    [[ "${INFO[2]}" != "" ]] && PGP_PORT="${INFO[2]}"
    [[ "${INFO[3]}" != "" ]] && WD_PORT="${INFO[3]}"

    echo "
other_pgpool_hostname$NUM = '$HOST'
other_pgpool_port$NUM = $PGP_PORT
other_pgpool_port$NUM = $PGP_PORT
other_wd_port$NUM = $WD_PORT
" >> $CONFIG_FILE
done
cat <<EOF >> $CONFIG_FILE
#------------------------------------------------------------------------------
# OTHERS
#------------------------------------------------------------------------------
relcache_expire = 0
                                   # Life time of relation cache in seconds.
                                   # 0 means no cache expiration(the default).
                                   # The relation cache is used for cache the
                                   # query result against PostgreSQL system
                                   # catalog to obtain various information
                                   # including table structures or if it's a
                                   # temporary table or not. The cache is
                                   # maintained in a pgpool child local memory
                                   # and being kept as long as it survives.
                                   # If someone modify the table by using
                                   # ALTER TABLE or some such, the relcache is
                                   # not consistent anymore.
                                   # For this purpose, cache_expiration
                                   # controls the life time of the cache.
relcache_size = 256
                                   # Number of relation cache
                                   # entry. If you see frequently:
                                                                   # "pool_search_relcache: cache replacement happend"
                                                                   # in the pgpool log, you might want to increate this number.

check_temp_table = on
                                   # If on, enable temporary table check in SELECT statements.
                                   # This initiates queries against system catalog of primary/master
                                                                   # thus increases load of master.
                                                                   # If you are absolutely sure that your system never uses temporary tables
                                                                   # and you want to save access to primary/master, you could turn this off.
                                                                   # Default is on.

check_unlogged_table = on
                                   # If on, enable unlogged table check in SELECT statements.
                                   # This initiates queries against system catalog of primary/master
                                   # thus increases load of master.
                                   # If you are absolutely sure that your system never uses unlogged tables
                                   # and you want to save access to primary/master, you could turn this off.
                                   # Default is on.
#------------------------------------------------------------------------------
# IN MEMORY QUERY MEMORY CACHE
#------------------------------------------------------------------------------
memory_cache_enabled = off
EOF

rm -f /var/run/pgpool/pgpool.pid /var/run/postgresql/.s.PGSQL.9999 2>/dev/null
echo "Start pgpool in foreground"
/usr/bin/pgpool -f ${CONFIG_FILE} -n
