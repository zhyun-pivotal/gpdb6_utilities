#!/usr/bin/env bash
source ~/.bash_profile
source /usr/local/greenplum-db/greenplum_path.sh

### Variable Setting
DATE="/usr/bin/date"
ECHO="/usr/bin/echo"
BASEDB="${PGDATABASE:-postgres}"
LOGFILE=/data/utilities/log/cron_vacuum_analyze_`$DATE '+%Y%m%d_%H%M'`.log
#VCOMMAND="VACUUM ANALYZE VERBOSE "
VCOMMAND="VACUUM ANALYZE "

### Declare a log function that records the date and time in all logs
log() { $ECHO "[$(date '+%F %T')] $*" >> $LOGFILE 2>&1 ; }

log "=== Start catalog tables VACUUM ANALYZE ==="

DBLIST=$(psql -qAtX -d "$BASEDB" -c \
"SELECT datname FROM pg_database WHERE datallowconn = 't' AND datname NOT IN ('template0', 'template1', 'postgres');")

if [[ -z "$DBLIST" ]]; then
  log "DB list is empty. Terminate the scripts."
  exit 0
fi

### Results
SUCCESS_COUNT=0
FAILURE_COUNT=0
TOTALTIME=0

### Handling cases where the db name contains spaces
#OLD_IFS="$IFS"
#IFS=$'\n'

#for db in $DBLIST; do
$ECHO "$DBLIST" | while read -r LINE
do
  DBNM=$($ECHO "$LINE")
  
  log " "
  log "=== Start DB: ${DBNM} ==="
  STARTSEC=$($DATE +%s)
  DB_SUCCESS=0
  DB_FAILURE=0

  TABLES=$(
    psql -qAtX -d "${DBNM}" -c \
    "SELECT n.nspname, c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'pg_catalog' AND c.relkind IN('r','t','m');" 2>> $LOGFILE
    )
	
  TABLES_RS=$?
  if [[ "$TABLES_RS" -ne 0 ]]; then
    log "[ERROR] Failed to get pg_catalog tables in DB : ${DBNM}"
    DB_FAILURE=1
    FAILURE_COUNT=$((FAILURE_COUNT + 1))
    ENDSEC=$($DATE +%s)
    ELAPSEDSEC=$((ENDSEC - STARTSEC))
    TOTALTIME=$((TOTALTIME + ELAPSEDSEC))
    log "=== Terminated DB : ${DBNM} (Elapsed : ${ELAPSEDSEC}sec, Success : ${DB_SUCCESS}, FAILURE : ${DB_FAILURE}) ==="
    continue
  fi

  if [[ -z "$TABLES" ]]; then
    log "[ERROR] No pg_catalog tables found in DB : ${DBNM}"
    ENDSEC=$($DATE +%s)
    ELAPSEDSEC=$((ENDSEC - STARTSEC))
    TOTALTIME=$((TOTALTIME + ELAPSEDSEC))
    log "=== Terminated DB : ${DBNM} (ELAPSEDSEC : ${ELAPSEDSEC}sec, Success : ${DB_SUCCESS}, FAILURE : ${DB_FAILURE}) ==="
    continue
  fi

  ### Execute VACUUM ANALYZE for each tables
  #for tbl in $TABLES; do
  $ECHO "$TABLES" | while read -r LINE
  do
    SCH=$($ECHO "$LINE" | cut -d'|' -f1)
    TBL=$($ECHO "$LINE" | cut -d'|' -f2)
	
    log " -> ${VCOMMAND} ${SCH}.${TBL}"
    psql -q -d "${DBNM}" -c "$VCOMMAND \"${SCH}\".\"${TBL}\";" >> "$LOGFILE" 2>&1
    
	VA_RS=$?
    if [ "$VA_RS" -eq 0 ]; then
  	  DB_SUCCESS=$((DB_SUCCESS + 1))
	else
	  log "[WARN] ${VCOMMAND} Fail : ${tbl}"
	  DB_FAILURE=$((DB_FAILURE + 1))
    fi
  done

  ENDSEC=$($DATE +%s)
  ELAPSEDSEC=$((ENDSEC - STARTSEC))
  log "=== Complete DB : ${DBNM} (ELAPSEDSEC : ${ELAPSEDSEC}sec, Success : ${DB_SUCCESS}, FAILURE : ${DB_FAILURE}) ==="
  
  TOTALTIME=$((TOTALTIME + ELAPSEDSEC))
  SUCCESS_COUNT=$((SUCCESS_COUNT + DB_SUCCESS))
  FAILURE_COUNT=$((FAILURE_COUNT + DB_FAILURE))
done

#IFS="$OLD_IFS"

log "=== Complete catalog tables VACUUM ANALYZE ==="
log " "
log "=============================================="
log " Total ELAPSEDSEC : ${TOTALTIME} sec"
log " Total Success : ${SUCCESS_COUNT}"
log " Total Failure : ${FAILURE_COUNT}"
log "=============================================="
