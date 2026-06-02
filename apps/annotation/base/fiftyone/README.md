# FiftyOne

This directory deploys FiftyOne as an internal ML dataset curation and visual
review workbench.

## Scope

- The FiftyOne app runs as a single-replica Deployment.
- MongoDB is deployed as a shared storage service from `storage/mongodb` and
  stores FiftyOne metadata.
- This first pass intentionally skips MongoDB backups, clustering, and
  hardening so the team can validate the app, database connection, and
  persistence.
- Access control is limited to the existing cluster/network controls for this
  first pass.

## Networking

FiftyOne uses the same shared Gateway pattern as Label Studio. The HTTPRoute
exposes:

```text
https://fiftyone.inspection.alpha.canada.ca
```

The Gateway listener is defined in `apps/louis/base/gateway.yaml`, and the
HTTPRoute is defined in `apps/annotation/base/httproute.yaml`. DNS should point
to the shared Gateway IP.

## Storage

FiftyOne metadata is stored in the shared MongoDB service:

```text
mongodb://mongodb.mongodb.svc.cluster.local:27017/fiftyone
```

Dataset media should be available to the FiftyOne pod through filesystem paths.
For S3-compatible storage such as Ceph or MinIO, mount or sync the bucket into
the pod before importing datasets.

The pod also mounts the annotation shared PVC at `/ailab`, matching the shared
workspace pattern used by Label Studio and the AI Lab shared work containers.

## Validation

```bash
kubectl get httproute -n annotation
kubectl get pods,svc,pvc -n annotation
kubectl get pods,svc,statefulset,pvc -n mongodb
kubectl logs deploy/fiftyone -n annotation
kubectl logs statefulset/mongodb -n mongodb
kubectl rollout restart deploy/fiftyone -n annotation
kubectl port-forward svc/fiftyone 5151:5151 -n annotation
```

Manual checks:

- Open `https://fiftyone.inspection.alpha.canada.ca`.
- Confirm the UI loads.
- Import or attach a small test dataset if appropriate.
- Restart the FiftyOne pod.
- Confirm dataset metadata remains available after restart.
- Restart the MongoDB pod and confirm metadata persists from the StatefulSet
  volume claim.
