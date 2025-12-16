#!/usr/bin/env bash
source ~/.bash_profile
source /usr/local/greenplum-db/greenplum_path.sh

### Variable Setting
BASEDB="${PGDATABASE:-gpadmin}"
EXEDATE="$(date +%Y-%m-%d)"
LOGFILE="/data/utilities/log/cron_vacuum_analyze_${EXEDATE}.log"
#VCOMMAND="VACUUM ANALYZE VERBOSE"
VCOMMAND="VACUUM ANALYZE"

log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOGFILE" ; }
log "Start VACUUM ANALYZE (pg_catalog only)"

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
OLD_IFS="$IFS"
IFS=$'\n'

for db in $DBLIST; do
  log " "
  log "=== VACUUM ANALYZE pg_catalog in DB: ${db} ==="
  STARTSEC=$(date +%s)
  DB_SUCCESS=0
  DB_FAILURE=0

  TABLES=$(
    psql -qAtX -d "${db}" -c \
    "SELECT 'pg_catalog.'||c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'pg_catalog' AND c.relkind IN('r','t','m');" 2>> "$LOGFILE"
    )
  TABLES_RESULTS=$?
  if [[ "$TABLES_RESULT" -ne 0 ]]; then
    log "[ERROR] Failed to get pg_catalog tables in DB : ${db}"
    DB_FAILURE=1
    FAILURE_COUNT=$((FAILURE_COUNT + 1))
    ENDSEC=$(date +%s)
    ELAPSEDSEC=$((ENDSEC - STARTSEC))
    TOTALTIME=$((TOTALTIME + ELAPSEDSEC))
    log "=== Completed DB name : ${db} (Elapsed : ${ELAPSEDSEC}sec, Success : ${DB_SUCCESS}, FAILURE : ${DB_FAILURE}) ==="
    continue
  fi

  if [[ -z "$TABLES" ]]; then
    log "No pg_catalog tables found in ${db}"
    ENDSEC=$(date +%s)
    ELAPSEDSEC=$((ENDSEC - STARTSEC))
    TOTALTIME=$((TOTALTIME + ELAPSEDSEC))
    log "=== Completed DB name : ${db} (ELAPSEDSEC : ${ELAPSEDSEC}sec, Success : ${DB_SUCCESS}, FAILURE : ${DB_FAILURE}) ==="
    continue
  fi

  ### Execute VACUUM ANALYZE for each tables
  for tbl in $TABLES; do
    log " -> ${VCOMMAND} ${tbl}"
    psql -q -d "$db" -c "$VCOMMAND ${tbl};" >> "$LOGFILE" 2>&1
    VA_RESULT=$?
    if [ "$VA_RESULT" -eq 0 ]; then
  	  DB_SUCCESS=$((DB_SUCCESS + 1))
	else
	  log "[WARN] ${VCOMMAND} Fail : ${tbl}"
	  DB_FAILURE=$((DB_FAILURE + 1))
    fi
  done

  ENDSEC=$(date +%s)
  ELAPSEDSEC=$((ENDSEC - STARTSEC))
  log "=== Completed DB name : ${db} (ELAPSEDSEC : ${ELAPSEDSEC}sec, Success : ${DB_SUCCESS}, FAILURE : ${DB_FAILURE}) ==="
  
  TOTALTIME=$((TOTALTIME + ELAPSEDSEC))
  SUCCESS_COUNT=$((SUCCESS_COUNT + DB_SUCCESS))
  FAILURE_COUNT=$((FAILURE_COUNT + DB_FAILURE))
done

IFS="$OLD_IFS"

log " "
log "=============================================="
log " Total ELAPSEDSEC : ${TOTALTIME}sec"
log " Total Success : ${SUCCESS_COUNT}"
log " Total Failure : ${FAILURE_COUNT}"
log "=============================================="


