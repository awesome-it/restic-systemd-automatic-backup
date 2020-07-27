#!/usr/bin/env bash
# Check my backup with  restic to Backblaze B2 for errors.
# This script is a modified version of:
# https://github.com/erikw/restic-systemd-automatic-backup/

# Exit on failure, pipe failure
set -e -o pipefail

restic_bin="ionice -c2 nice -n19 /usr/local/sbin/restic"

# Clean up lock if we are killed.
# If killed by systemd, like $(systemctl stop restic), then it kills the whole cgroup and all it's subprocesses.
# However if we kill this script ourselves, we need this trap that kills all subprocesses manually.
exit_hook() {
	echo "In exit_hook(), being killed" >&2
	jobs -p | xargs kill
	restic unlock
}
trap exit_hook INT TERM


source /etc/restic/restic_env.sh

# Check if every necessary envvar is set before continuing
envvars=( BACKUP_PATHS BACKUP_EXCLUDES RETENTION_DAYS RETENTION_WEEKS RETENTION_MONTHS RETENTION_YEARS )
for envvar in "${envvars[@]}"
do
    if [ -z "${!envvar}" ]; then
        echo "Environment variable ${envvar} missing"
        exit 1
    fi
done

# How many network connections to set up to B2. Default is 5.
B2_CONNECTIONS=50

# Remove locks from other stale processes to keep the automated backup running.
# NOTE nope, don't unlock like restic_backup.sh. restic_backup.sh should take precedence over this script.
#restic unlock &
#wait $!

# Check repository for errors.
$restic_bin check \
	--option b2.connections=$B2_CONNECTIONS \
	--verbose &
wait $!
