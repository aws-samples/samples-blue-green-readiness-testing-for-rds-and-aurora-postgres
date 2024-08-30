#!/bin/bash

# ============================================================================
# Script Name: BlueGreen-precheck.sh
# Author: Peter Celentano
# Alias: @pcelent
# Version: v1.0
# Date: 2024-08-27
# Description: This script checks RDS/Aurora PostgreSQL databases for readiness to use
#              with Blue/Green deployments by identifying various issues such as
#              missing primary keys, replica identity settings, presence of
#              logical replication slots, pg_largeobjects, and foreign tables.
# ============================================================================

# ============================================================================
# Version History
# ----------------------------------------------------------------------------
# v1.0 - 2024-08-27 - Peter Celentano
#      - Initial release.
# ============================================================================

# Default values
DB_HOST=""
DB_PORT="5432"
DB_USER="postgres"
DB_PASS=""
LOG_FILE=""
NO_LOG=0
DB_ENDPOINT_FILE=""
DB_ENDPOINT_USER=""
DB_ENDPOINT_PASS=""

# Help message
function usage() {
  printf "Usage: %s [-h host] [-p port] [-U user] [-P password] [-l log_prefix] [--no-log] [--endpoints-file file] [--file-user user] [--file-password password]\n" "$0"
  printf "  -h, --host          Database host (default: localhost)\n"
  printf "  -p, --port          Database port (default: 5432)\n"
  printf "  -U, --user          Database user (default: postgres)\n"
  printf "  -P, --password      Database password\n"
  printf "  -l, --log           Log file prefix (logs to a timestamped file)\n"
  printf "  --no-log            Do not log output\n"
  printf "  --endpoints-file    Path to file containing a list of host:dbname pairs\n"
  printf "  --file-user         Database user for the endpoints in the file\n"
  printf "  --file-password     Database password for the endpoints in the file\n"
  exit 1
}

# Parse input flags
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--host)
      DB_HOST="$2"
      shift 2
      ;;
    -p|--port)
      DB_PORT="$2"
      shift 2
      ;;
    -U|--user)
      DB_USER="$2"
      shift 2
      ;;
    -P|--password)
      DB_PASS="$2"
      shift 2
      ;;
    -l|--log)
      LOG_FILE="$2"
      shift 2
      ;;
    --no-log)
      NO_LOG=1
      shift
      ;;
    --endpoints-file)
      DB_ENDPOINT_FILE="$2"
      shift 2
      ;;
    --file-user)
      DB_ENDPOINT_USER="$2"
      shift 2
      ;;
    --file-password)
      DB_ENDPOINT_PASS="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

# Prepare log file if needed
if [[ $NO_LOG -eq 0 ]]; then
  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  LOG_FILE="${LOG_FILE}_${TIMESTAMP}.log"
fi

# Function to execute SQL query and handle logging
function exec_query() {
  local query="$1"
  local result=""
  if [[ -z $DB_PASS ]]; then
    result=$(psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -t -c "$query")
  else
    result=$(PGPASSWORD=$DB_PASS psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -t -c "$query")
  fi
  if [[ $NO_LOG -eq 0 ]]; then
    printf "%s\n" "$result" >> "$LOG_FILE"
  else
    printf "%s\n" "$result"
  fi
  printf "%s\n" "$result"
}

# Function to get a list of all databases accessible by the user, ignoring specific databases
function get_databases() {
  psql -h $DB_HOST -p $DB_PORT -U $DB_USER -t -c "SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ('rdsadmin', 'template0', 'template1');" -A
}

# Main function to iterate over all databases and propose fixes or raise warnings
function check_all_databases() {
  local databases
  databases=$(get_databases)

  local issues_found=0

  for db in $databases; do
    printf "\n============================================================\n"
    printf "Checking database: %s\n" "$db"
    printf "============================================================\n"
    DB_NAME=$db

    # Check for missing primary keys or REPLICA IDENTITY FULL
    fix_tables_query="
      SELECT
        'ALTER TABLE ' || n.nspname || '.' || c.relname ||
        CASE
          WHEN indisprimary IS NULL AND c.relreplident != 'f' THEN
            ' ADD PRIMARY KEY (' || string_agg(a.attname, ', ') || ');'
          WHEN indisprimary IS NULL AND c.relreplident = 'f' THEN
            ' SET REPLICA IDENTITY FULL; ADD PRIMARY KEY (' || string_agg(a.attname, ', ') || ');'
          WHEN c.relreplident != 'f' THEN
            ' SET REPLICA IDENTITY FULL;'
          ELSE
            ''
        END AS proposed_fix
      FROM
        pg_class c
      JOIN
        pg_namespace n ON n.oid = c.relnamespace
      JOIN
        pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
      LEFT JOIN
        pg_index i ON i.indrelid = c.oid AND i.indisprimary
      WHERE
        c.relkind = 'r' AND n.nspname NOT IN ('pg_catalog', 'information_schema')
      GROUP BY n.nspname, c.relname, c.relreplident, indisprimary;
    "

    proposed_fixes=$(exec_query "$fix_tables_query")
    if [[ -n $proposed_fixes ]]; then
      printf "\nProposed commands to fix tables in %s:\n" "$db"
      printf "%s\n" "$proposed_fixes"
      issues_found=1
    fi

    # Check for presence of pg_largeobject
    printf "============================================================\n"
    printf "Checking for incompatable pg_largeobjects"
    printf "\n ... ... \n"
    check_pg_largeobject="SELECT EXISTS (SELECT 1 FROM pg_largeobject);"
    has_pg_largeobject=$(exec_query "$check_pg_largeobject" | tr -d '[:space:]')
    if [[ $has_pg_largeobject == "t" ]]; then
      printf "\nWARNING: The database %s contains pg_largeobjects, which cannot be replicated.\n" "$db"
      printf "============================================================\n"
      issues_found=1 ; else
      printf "No incompatable pg_largeobjects found\n"
      printf "============================================================\n"
    fi

    # Check for presence of foreign tables (corrected)
    printf "===============================================================================================\n"
    printf "Checking for foreign tables which will need to be recreated in the Green environment manually"
    printf "\n ... ... \n"
    check_foreign_tables="SELECT EXISTS (SELECT * FROM information_schema.foreign_tables);"
    has_foreign_tables=$(exec_query "$check_foreign_tables" | tr -d '[:space:]')
    if [[ $has_foreign_tables == "t" ]]; then
     printf "\nWARNING: The database %s contains foreign tables, which cannot be replicated.\n" "$db"
     printf "===============================================================================================\n"
      issues_found=1; else
    printf "No foreign tables exist on database %s\n"
    printf "===============================================================================================\n"

    fi
  done

  # Check for logical replication slots across all databases
    printf "\n======================================================================================================================================\n"
    printf "Checking cluster-wide for logical replication slots: $DB_HOST\n" "$db"
    printf "======================================================================================================================================\n"
  check_logical_slots="SELECT EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_type = 'logical');"
  has_logical_slots=$(exec_query "$check_logical_slots" | tr -d '[:space:]')
  if [[ $has_logical_slots == "t" ]]; then
    printf "\nWARNING: Logical replication slots exist in the cluster.\n"
    issues_found=1; else
    printf "\n No logical replication slots found cluster-wide"
  fi

  # Output readiness message
  if [[ $issues_found -eq 1 ]]; then
    printf "\n==================================================================================================================================\n"
    printf "Cluster $DB_HOST is NOT READY for usage with Blue/Green Deployments\n"
    printf "Please check the script output, fix any issues listed, and try again.\n"
    printf "==================================================================================================================================\n"
  else
    printf "\n===========================================================================================================\n"
    printf "Cluster $DB_HOST is READY for usage with Blue/Green Deployments\n"
    printf "============================================================================================================\n"
  fi
}

# Function to process the list of provided endpoints from a file
function process_endpoints_file() {
  while IFS= read -r line; do
    IFS=':' read -r -a parts <<< "$line"
    DB_HOST="${parts[0]}"
    DB_NAME="${parts[1]}"
    DB_USER="$DB_ENDPOINT_USER"
    DB_PASS="$DB_ENDPOINT_PASS"
    printf "\nProcessing endpoint: %s:%s\n" "$DB_HOST" "$DB_NAME"
    check_all_databases
  done < "$DB_ENDPOINT_FILE"
}

# Decide whether to use provided endpoints file or default host and database name
if [[ -n $DB_ENDPOINT_FILE ]]; then
  if [[ -z $DB_ENDPOINT_USER || -z $DB_ENDPOINT_PASS ]]; then
    printf "Error: --file-user and --file-password must be provided when using --endpoints-file\n"
    exit 1
  fi
  printf "\nUsing database endpoints from file: %s\n" "$DB_ENDPOINT_FILE"
  process_endpoints_file
else
  printf "\nUsing default host and database name input options\n"
  check_all_databases
fi
