#!/bin/sh
set -eu
export ETCDCTL_API=3 LC_ALL=C
timestamp=$(date -u +%F-%H%M%S)
snapshot="/backup/etcd-snapshot-$timestamp.db"
staging=$(mktemp -d /backup/.etcd-snapshot.XXXXXX)
trap 'rm -rf "$staging"' EXIT
trap 'exit 1' HUP INT TERM

etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/pki/ca.crt \
  --cert=/etc/etcd/pki/server.crt \
  --key=/etc/etcd/pki/server.key \
  snapshot save "$staging/snapshot.db"
etcdctl snapshot status "$staging/snapshot.db"
# Publish the checked file without replacing an existing snapshot.
ln -T "$staging/snapshot.db" "$snapshot"

backup_day=${timestamp%-*}
daily_start=$(date -u -d "$backup_day 13 days ago" +%Y%m%d)
weekly_end=$(date -u -d "$backup_day 14 days ago" +%F)
weekly_end_weekday=$(date -u -d "$weekly_end" +%u)
# Include the week containing the first eligible day and seven older weeks.
weekly_start=$(date -u -d "$weekly_end $((weekly_end_weekday - 1 + 7 * 7)) days ago" +%Y%m%d)

# Process the newest snapshot in each period first.
set --
for saved in /backup/etcd-snapshot-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9].db; do
  if [ -f "$saved" ] && [ ! -L "$saved" ]; then
    set -- "$saved" "$@"
  fi
done
if [ "${1:-}" != "$snapshot" ]; then
  echo "Skipping cleanup because the new snapshot is not the newest file" >&2
  exit 0
fi

previous_period=
months=0
prune_list="$staging/prune-list"
: > "$prune_list"
for saved do
  saved_timestamp=${saved##*/etcd-snapshot-}
  calendar=$(date -u -d "${saved_timestamp%-*}" '+%Y%m%d %G-W%V %Y-%m')
  read -r day week month <<EOF
$calendar
EOF
  if [ "$day" -ge "$daily_start" ]; then
    period=$day
  elif [ "$day" -ge "$weekly_start" ]; then
    period=$week
  else
    period=$month
  fi
  if [ "$period" != "$previous_period" ]; then
    previous_period=$period
    if [ "$day" -ge "$weekly_start" ]; then
      continue
    fi
    months=$((months + 1))
    if [ "$months" -le 3 ]; then
      continue
    fi
  fi
  printf '%s\n' "$saved" >> "$prune_list"
done

while IFS= read -r saved; do
  rm -f "$saved"
  printf 'Removed old snapshot %s\n' "$saved"
done < "$prune_list"
