#!/usr/bin/env bash
# Make backup my system with restic to Backblaze B2.
# This script is a modified version of:
# https://github.com/erikw/restic-systemd-automatic-backup/

# Exit on failure, pipe failure
set -e -o pipefail

restic_bin="$(which ionice) -c2 nice -n19 $(which restic)"

# Clean up lock if we are killed.
# If killed by systemd, like $(systemctl stop restic), then it kills the whole cgroup and all it's subprocesses.
# However if we kill this script ourselves, we need this trap that kills all subprocesses manually.
exit_hook() {
	echo "In exit_hook(), being killed" >&2
	jobs -p | xargs kill
	$restic_bin unlock
}
trap exit_hook INT TERM

# Set all environment variables like
# B2_ACCOUNT_ID, B2_ACCOUNT_KEY, RESTIC_REPOSITORY etc.
source /etc/restic/config

# Check if every necessary envvar is set before continuing
envvars=( BACKUP_PATHS BACKUP_EXCLUDES RETENTION_DAYS RETENTION_WEEKS RETENTION_MONTHS RETENTION_YEARS )
for envvar in "${envvars[@]}"
do
    if [ -z "${!envvar}" ]; then
        echo "Environment variable ${envvar} missing"
        exit 1
    fi
done

# Check for backup_excludes in homedirs
for dir in /home/*
do
	if [ -f "$dir/.backup_exclude" ]
	then
		BACKUP_EXCLUDES+=" --exclude-file $dir/.backup_exclude"
	fi
done

BACKUP_TAG=auto-backup

# How many network connections to set up to B2. Default is 5.
B2_CONNECTIONS=50

# NOTE start all commands in background and wait for them to finish.
# Reason: bash ignores any signals while child process is executing and thus my trap exit hook is not triggered.
# However if put in subprocesses, wait(1) waits until the process finishes OR signal is received.
# Reference: https://unix.stackexchange.com/questions/146756/forward-sigterm-to-child-in-bash

# Remove locks from other stale processes to keep the automated backup running.
$restic_bin unlock &
wait $!

# Do the backup!
# See restic-backup(1) or http://restic.readthedocs.io/en/latest/040_backup.html
# --one-file-system makes sure we only backup exactly those mounted file systems specified in $BACKUP_PATHS, and thus not directories like /dev, /sys etc.
# --tag lets us reference these backups later when doing restic-forget.
restic_tmp_out=$(mktemp /tmp/restic-backup.XXXXXX)

BACKUP_PARAMS="${BACKUP_PARAMS}"
if [[ -z "$RESTIC_SKIP_ONE_FILE_SYSTEM" ]] ; then
  BACKUP_PARAMS="$BACKUP_PARAMS --one-file-system"
fi

$restic_bin backup $BACKUP_PARAMS \
	--json \
	--tag $BACKUP_TAG \
	--option b2.connections=$B2_CONNECTIONS \
  --exclude-caches \
	$BACKUP_EXCLUDES \
	$BACKUP_PATHS > $restic_tmp_out &
wait $!

# collect summary stats for promtheus node exporter
if [[ -n "$BACKUP_PROMETHEUS_TXT_COLLECTOR" ]] ; then

  if [[ ! -d "$BACKUP_PROMETHEUS_TXT_COLLECTOR" ]] ; then
    mkdir -p "$BACKUP_PROMETHEUS_TXT_COLLECTOR"
  fi
  
  cat $restic_tmp_out | jq -r '. | select(.message_type == "summary") | "restic_stats_last_snapshot_duration \(.total_duration)\nrestic_stats_last_last_snapshot_bytes_processed \(.total_bytes_processed)\nrestic_stats_last_snapshot_files_processed \(.total_files_processed)"' > $BACKUP_PROMETHEUS_TXT_COLLECTOR/restic-last-snapshot.prom.$$
  mv $BACKUP_PROMETHEUS_TXT_COLLECTOR/restic-last-snapshot.prom.$$ $BACKUP_PROMETHEUS_TXT_COLLECTOR/restic-last-snapshot.prom
  
  # collect additional stats for prometheus node exporter
  $restic_bin stats --json latest | jq -r '"restic_stats_last_snapshot_total_size_bytes \(.total_size)\nrestic_stats_last_snapshot_file_count \(.total_file_count)"' > $BACKUP_PROMETHEUS_TXT_COLLECTOR/restic-stats-latest-snapshot.prom.$$
  mv $BACKUP_PROMETHEUS_TXT_COLLECTOR/restic-stats-latest-snapshot.prom.$$ $BACKUP_PROMETHEUS_TXT_COLLECTOR/restic-stats-latest-snapshot.prom
  
  $restic_bin stats --mode raw-data --json | jq -r '"restic_stats_total_size_bytes \(.total_size)"' > $BACKUP_PROMETHEUS_TXT_COLLECTOR/restic-stats-total.prom.$$
  mv $BACKUP_PROMETHEUS_TXT_COLLECTOR/restic-stats-total.prom.$$ $BACKUP_PROMETHEUS_TXT_COLLECTOR/restic-stats-total.prom
  
  $restic_bin snapshots --json latest | jq -r '.[].time | split(".")[0] | strptime("%Y-%m-%dT%H:%M:%S") | mktime | "restic_stats_last_snapshot_timestamp \(.)"' > $BACKUP_PROMETHEUS_TXT_COLLECTOR/restic-stats-latest-snapshot-timestamp.prom.$$
  mv $BACKUP_PROMETHEUS_TXT_COLLECTOR/restic-stats-latest-snapshot-timestamp.prom.$$ $BACKUP_PROMETHEUS_TXT_COLLECTOR/restic-stats-latest-snapshot-timestamp.prom
  
  du -s /root/.cache/restic | awk '{ printf "restic_stats_cache_total_size_bytes %d\n",$1 }' > $BACKUP_PROMETHEUS_TXT_COLLECTOR/restic-stats-cache.prom.$$
  mv $BACKUP_PROMETHEUS_TXT_COLLECTOR/restic-stats-cache.prom.$$ $BACKUP_PROMETHEUS_TXT_COLLECTOR/restic-stats-cache.prom
  
fi

# clean up
rm -f $restic_tmp_out

# Dereference and delete/prune old backups.
# See restic-forget(1) or http://restic.readthedocs.io/en/latest/060_forget.html
# --group-by only the tag and path, and not by hostname. This is because I create a B2 Bucket per host, and if this hostname accidentially change some time, there would now be multiple backup sets.
$restic_bin forget \
	--tag $BACKUP_TAG \
	--option b2.connections=$B2_CONNECTIONS \
        --prune \
	--group-by "paths,tags" \
	--keep-daily $RETENTION_DAYS \
	--keep-weekly $RETENTION_WEEKS \
	--keep-monthly $RETENTION_MONTHS \
	--keep-yearly $RETENTION_YEARS &
wait $!

# Check repository for errors.
# NOTE this takes much time (and data transfer from remote repo?), do this in a separate systemd.timer which is run less often.
#restic check &
#wait $!

echo "Backup & cleaning is done."
