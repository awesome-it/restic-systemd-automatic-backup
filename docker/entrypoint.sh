#!/bin/bash
set -e

echo "Running scripts from \"/backup/scripts\" ..."
for script in $(find /backup/scripts -type f)
do
  echo "Running \"${script}\" ..."
  /bin/bash $script
done

echo "Running \"restic_backup.sh\" ..."
/usr/local/sbin/restic_backup.sh

if [[ -z "$SKIP_RESTIC_CHECK" ]] ; then
  echo "Running \"restic_check.sh\" ..."
  /usr/local/sbin/restic_check.sh
fi

exit 0
