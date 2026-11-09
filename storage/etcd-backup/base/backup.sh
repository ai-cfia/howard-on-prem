#!/bin/sh
set -eu
export ETCDCTL_API=3 LC_ALL=C
snapshot="/backup/etcd-snapshot-$(date +%F-%H%M%S).db"
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

min_free_kib=$((3 * 1024 * 1024))
min_snapshots=4
# Timestamped names sort oldest first in the C locale.
set --
for saved in /backup/etcd-snapshot-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9].db; do
  if [ -f "$saved" ] && [ ! -L "$saved" ]; then
    set -- "$@" "$saved"
  fi
done

while :; do
  usage=$(df -Pk /backup)
  free_kib=$(printf '%s\n' "$usage" | awk 'NR == 2 {print $4}')
  case "$free_kib" in
    ''|*[!0-9]*)
      echo "Cannot read available space on the backup PVC" >&2
      exit 1
      ;;
  esac
  if [ "$free_kib" -ge "$min_free_kib" ]; then
    break
  fi
  if [ "$#" -le "$min_snapshots" ] || [ "$1" = "$snapshot" ]; then
    echo "Backup PVC is below 3 GiB free and has no eligible snapshots to prune" >&2
    break
  fi
  rm -f "$1"
  printf 'Removed old snapshot %s\n' "$1"
  shift
done
