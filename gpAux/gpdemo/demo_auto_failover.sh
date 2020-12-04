
if [ -z "${MASTER_DATADIR}" ]; then
  DATADIRS=${DATADIRS:-`pwd`/datadirs}
else
  DATADIRS="${MASTER_DATADIR}/datadirs"
fi

QDDIR=$DATADIRS/qddir/demoDataDir-1
STANDBYDIR=$DATADIRS/standby

function init_nodes() {
sed -i 's/#hot_standby = off/hot_standby = on/' $QDDIR/postgresql.conf
sed -i 's/#hot_standby = off/hot_standby = on/' $STANDBYDIR/postgresql.conf
MASTER_DATA_DIRECTORY=$QDDIR PGPORT=7000 gpstop -air

pg_autoctl create monitor --pgdata $DATADIRS/pgmonitor --hostname localhost --pgport 7999 --auth trust --ssl-self-signed
pg_autoctl run --pgdata $DATADIRS/pgmonitor &

MPID=$!
sleep 10 # wait until the monitor is ready
echo "MPID = $MPID"

pgdata=$QDDIR
pg_ctl stop -D $pgdata
pg_autoctl create postgres --pgdata $pgdata --pgport 7000 --hostname localhost --name pgm --monitor 'postgres://autoctl_node@localhost:7999/pg_auto_failover?sslmode=require' --auth trust --ssl-self-signed --gp_dbid 1 --gp_role dispatch
echo 'hostssl "postgres" "gpadmin" localhost trust' >> $pgdata/pg_hba.conf
echo 'hostssl all "pgautofailover_monitor" localhost trust' >>  $pgdata/pg_hba.conf
echo 'host "postgres" "gpadmin" localhost trust' >> $pgdata/pg_hba.conf
echo 'host all "pgautofailover_monitor" localhost trust' >>  $pgdata/pg_hba.conf
pg_autoctl run --pgdata $pgdata &
QPID=$!
echo "PID of the pg_autoctl in master = $QPID"

pg_ctl stop -D $STANDBYDIR
pg_autoctl create postgres --pgdata $STANDBYDIR --pgport 7001 --hostname localhost --name pgs --monitor 'postgres://autoctl_node@localhost:7999/pg_auto_failover?sslmode=require' --auth trust --ssl-self-signed --gp_dbid 8 --gp_role dispatch

# Add missing hba rules.
# hostssl "postgres" "gpadmin" localhost trust # Auto-generated by pg_auto_failover
# hostssl all "pgautofailover_monitor" localhost trust # Auto-generated by pg_auto_failover

pgdata=$STANDBYDIR
echo 'hostssl "postgres" "gpadmin" localhost trust' >> $pgdata/pg_hba.conf
echo 'hostssl all "pgautofailover_monitor" localhost trust' >>  $pgdata/pg_hba.conf
echo 'host "postgres" "gpadmin" localhost trust' >> $pgdata/pg_hba.conf
echo 'host all "pgautofailover_monitor" localhost trust' >>  $pgdata/pg_hba.conf
pg_autoctl run --pgdata $pgdata &
SPID=$!
echo "PID of the pg_autoctl in standby = $SPID"

sleep 1
# kill $QPID
wait $MPID
}

function start_cluster() {
gpstart -a
pg_ctl stop -D $QDDIR
pg_ctl stop -D $STANDBYDIR
pg_autoctl run --pgdata $DATADIRS/pgmonitor &
sleep 5

pg_autoctl run --pgdata $QDDIR &
sleep 3

pg_autoctl run --pgdata $STANDBYDIR &
sleep 2
}

function stop_cluster() {
pkill -9 pg_autoctl 2>/dev/null
gpstop -af
pkill postgres
}
function restart_cluster() {
stop_cluster
start_cluster
}

case $1 in
	init_nodes)
		init_nodes
		;;
    start)
        start_cluster
        ;;
    stop)
        stop_cluster
        ;;
    restart)
        restart_cluster
        ;;
	*)
		echo "??? $1"
		;;
esac
