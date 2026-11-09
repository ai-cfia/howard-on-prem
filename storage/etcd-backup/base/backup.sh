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

days_kept=0
weeks_kept=0
months_kept=0
daily_bucket=
weekly_bucket=
monthly_bucket=
last_snapshot_month=
prune_list="$staging/prune-list"
: > "$prune_list"
for saved do
  saved_timestamp=${saved##*/etcd-snapshot-}
  calendar=$(date -u -d "${saved_timestamp%-*}" '+%F %G-W%V %Y-%m')
  read -r day week month <<EOF
$calendar
EOF
  previous_month=$last_snapshot_month
  last_snapshot_month=$month

  # Finish the last daily or weekly bucket before moving to the next tier.
  if [ "$days_kept" -lt 14 ] || [ "$day" = "$daily_bucket" ]; then
    if [ "$day" != "$daily_bucket" ]; then
      daily_bucket=$day
      days_kept=$((days_kept + 1))
      continue
    fi
  elif [ "$weeks_kept" -lt 8 ] || [ "$week" = "$weekly_bucket" ]; then
    if [ "$week" != "$weekly_bucket" ]; then
      weekly_bucket=$week
      weeks_kept=$((weeks_kept + 1))
      continue
    elif [ "$month" != "$previous_month" ]; then
      # A week can span two months. Keep the earlier month's newest copy.
      continue
    fi
  elif [ "$months_kept" -lt 3 ] && [ "$month" != "$monthly_bucket" ]; then
    monthly_bucket=$month
    months_kept=$((months_kept + 1))
    continue
  fi
  printf '%s\n' "$saved" >> "$prune_list"
done

while IFS= read -r saved; do
  rm -f "$saved"
  printf 'Removed old snapshot %s\n' "$saved"
done < "$prune_list"
