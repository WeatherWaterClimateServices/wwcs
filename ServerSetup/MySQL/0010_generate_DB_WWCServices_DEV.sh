#!/bin/bash
#!/bin/bash
set -e

# Require root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root (not just sudo). Aborting." >&2
  exit 1
fi

## extract current structure
mysqldump --no-data --routines --events --triggers --databases \
  --skip-add-drop-table WWCServices \
  | sed 's/`WWCServices`/`WWCServices_DEV`/g' \
  | sed 's/^CREATE TABLE /CREATE TABLE IF NOT EXISTS /' \
  > migrate_WWCServices_DEV.sql

## create db/tables, only if not existant
mysql < migrate_WWCServices_DEV.sql

## clean up
rm migrate_WWCServices_DEV.sql

## grant permissions
mysql -e "GRANT INSERT, UPDATE, DELETE, SELECT ON WWCServices.* TO 'wwcs'@'localhost' WITH GRANT OPTION;"
