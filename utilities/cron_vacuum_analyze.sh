#!/usr/bin/env bash
source ~/.bash_profile
source /usr/local/greenplum-db/greenplum_path.sh

### Variable Setting
BASE_DB="${PGDATABASE:-gpadmin}"
RUN_TS="$(date +%Y-%m-%d)"
LOG_FILE="/data/utilities/log/cron_vacuum_analyze_${RUN_TS}.log"

log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE" ; }
log "Start VACUUM ANALYZE (pg_catalog only)"

DB_LIST=$(psql -qAtX -d "$BASE_DB" -c \
"SELECT datname FROM pg_database WHERE datallowconn = 't' AND datname NOT IN ('template0', 'template1', 'postgres');")

if [[ -z "$DB_LIST" ]]; then
  log "DB list is empty. Terminate the scripts."
  exit 0
fi

### Results
SUCCESS_COUNT=0
FAILURE_COUNT=0
TOTAL_TIME=0

### Handling cases where the db name contains spaces
OLD_IFS="$IFS"
IFS=$'\n'

for db in $DB_LIST; do
  log " "
  log "=== VACUUM ANALYZE pg_catalog in DB: ${db} ==="
  log "Start at : $(date +%Y-%m-%d)" 
  start_s=$(date +%s)
  DB_SUCCESS=0
  DB_FAILURE=0

  TABLES=$(
    psql -qAtX -d "$db" -c \
    "SELECT 'pg_catalog.'||c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'pg_catalog' AND c.relkind IN('r','t','m');" 2>> "$LOG_FILE"
    )
  TABLES_RESULTS=$?
  if [[ "$TABLES_RESULT" -ne 0 ]]; then
    log "[ERROR] Failed to get pg_catalog tables in $[db]"
    DB_FAILURE=1
    FAILURE_COUNT=$((FAILURE_COUNT + 1))
    end_s=$(date +%s)
    elapsed=$((end_s - start_s))
    TOTAL_TIME=$((TOTAL_TIME + elapsed))
	log "Completed at : $(date +%Y-%m-%d)" 
    log "=== Completed DB name : ${db} (elapsed : ${elapsed}sec, Success : ${DB_SUCCESS}, FAILURE : ${DB_FAILURE}) ==="
    continue
  fi

  if [[ -z "$TABLES" ]]; then
    log "No pg_catalog tables found in $[db]"
    end_s=$(date +%s)
    elapsed=$((end_s - start_s))
    TOTAL_TIME=$((TOTAL_TIME + elapsed))
	log "Completed at : $(date +%Y-%m-%d)" 
    log "=== Completed DB name : ${db} (elapsed : ${elapsed}sec, Success : ${DB_SUCCESS}, FAILURE : ${DB_FAILURE}) ==="
    continue
  fi

  ### Execute VACUUM ANALYZE for each tables
  for tbl in $TABLES; do
    log " -> VACUUM ANALYZE VERBOSE $tbl"
    psql -q -d "$db" -c "VACUUM ANALYZE VERBOSE $tbl;" >> "$LOG_FILE" 2>&1
    VA_RESULT=$?
    if [ "$VA_RESULT" -eq 0 ]; then
  	  DB_SUCCESS=$((DB_SUCCESS + 1))
	else
	  log "[WARN] VACUUM Fail : $tbl"
	  DB_FAILURE=$((DB_FAILURE + 1))
    fi
  done

  end_s=$(date +%s)
  elapsed=$((end_s - start_s))
  log "Completed at : $(date +%Y-%m-%d)" 
  log "=== Completed DB name : ${db} (elapsed : ${elapsed}sec, Success : ${DB_SUCCESS}, FAILURE : ${DB_FAILURE}) ==="
  TOTAL_TIME=$((TOTAL_TIME + elapsed))
  SUCCESS_COUNT=$((SUCCESS_COUNT + DB_SUCCESS))
  FAILURE_COUNT=$((FAILURE_COUNT + DB_FAILURE))
done

IFS="$OLD_IFS"

log " "
log "=============================================="
log " Total Elapsed : ${TOTAL_TIME}sec"
log " Total Success : ${SUCCESS_COUNT}"
log " Total Failure : ${FAILURE_COUNT}"
log "=============================================="


