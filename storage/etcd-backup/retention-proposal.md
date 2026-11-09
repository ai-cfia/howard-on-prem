# etcd backup retention proposal

This is a proposal for [issue #463](https://github.com/ai-cfia/howard-on-prem/issues/463).
It does not change the backup job or authorize deletion. Preserve all existing
snapshots while restoring a working backup.

## Retention and capacity

- Start the discussion with four verified weekly snapshots on the PVC and
  twelve verified weekly copies in approved, encrypted storage that remains
  available if the cluster or its Ceph storage is lost. Confirm the cadence
  and retention counts against the team's recovery requirements.
- Size the PVC for the retained files, one new snapshot, and growth headroom.
  Before each run, check available bytes and inodes against the expected
  snapshot size and a safety margin. If there is not enough room, report the
  failure and alert without deleting any backups.
- Prevent overlapping backup writers, including scheduled and manual runs.

## Backup and cleanup order

1. Save a new snapshot at a unique path and verify it with a compatible etcd
   tool. Keep incomplete files separate from completed snapshots.
2. Copy the verified snapshot to the independent destination and verify the
   copy. Record its time, size, checksum, and destination without recording
   credentials.
3. Only after both checks pass, apply the approved retention policy to
   identified snapshot files. Do not remove a local copy unless its verified
   independent copy exists and the minimum recovery points will still be
   retained. Do not prune after a failed backup, verification, or copy.

## Before enabling cleanup

- Check whether the existing [Velero schedule](../velero/helm/values.yaml)
  preserves recoverable snapshot file contents outside the Ceph volume.
  A backup of the PVC object alone is not sufficient.
- Test restoring a snapshot from the independent destination in an isolated
  environment. Do not restore over the live cluster.
- Add alerts for low backup space and overdue successful backups. Review a
  dry run of the proposed cleanup and test that failures leave prior
  snapshots untouched.
