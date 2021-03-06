#!/bin/sh

if [ $# -ne 1 ] ; then
  echo Please supply node id to be recovered
  exit 1
fi
echo Find host from node_id $1
pcp_host=$(pcp_node_info -h pgpool -p 9898 -w $1 | cut -f1 -d" ")
echo Found host $pcp_host
echo Find the state of this host in nodes
> /tmp/nodes.tmp
psql -U repmgr -h pgpool -p 9999 repmgr -t -c "select node_name,active,type from nodes;" > /tmp/nodes.tmp
repl_active=$(cat /tmp/nodes.tmp | sed -e "s/ //g" | grep "^${pcp_host}" | cut -f2 -d"|")
repl_type=$(cat /tmp/nodes.tmp | sed -e "s/ //g" | grep "^${pcp_host}" | cut -f3 -d"|")
echo repl_active = ${repl_active} - repl_type = ${repl_type}
if [ $repl_active == 't' -a $repl_type == 'primary' ] ; then
 echo ERROR: this node is active and is a primary
 exit 1
fi
echo Doing pcp_recovery_node of $1, it will take long. Check the pgpool log file for progress
pcp_recovery_node -h pgpool -p 9898 -w $1
exit $?

