export RESTIC_PASSWORD_FILE="${RESTIC_PASSWORD_FILE:-/etc/restic/password}"

if [[ -n "$RESTIC_PASSWORD" ]] ; then
  echo "$RESTIC_PASSWORD" > $RESTIC_PASSWORD_FILE
fi

# Retention Times
export RETENTION_DAYS="${RETENTION_DAYS:-14}"
export RETENTION_WEEKS="${RETENTION_WEEKS:-16}"
export RETENTION_MONTHS="${RETENTION_MONTHS:-18}"
export RETENTION_YEARS="${RETENTION_YEARS:-3}"

# Backup Pathes & Excludes
export BACKUP_PATHS="${BACKUP_PATHS:-/backup/data}"
export BACKUP_EXCLUDES="${BACKUP_EXCLUDES:---exclude-file /etc/restic/backup_exclude}"

# Cache Directory
export RESTIC_CACHE_DIR=${RESTIC_CACHE_DIR:-"/root/.cache/restic"}