# FiftyOne

FiftyOne is deployed as an internal dataset curation and visual review
workbench for AI Lab image datasets.

## Runtime

- The app runs as a single-replica Deployment.
- Metadata is stored in the shared MongoDB service:

  ```text
  mongodb://mongodb.mongodb.svc.cluster.local:27017/fiftyone
  ```

- The image is built in `ai-cfia/devops` under `dockerfiles/fiftyone`.
- The deployment consumes the published image from GHCR.

## Plugins

The custom image extends:

```text
voxel51/fiftyone:1.15.0-python3.9-20260502
```

Installed plugins:

```text
@voxel51/annotation
@voxel51/io
@voxel51/brain
@voxel51/utils
```

`@voxel51/delegation` is intentionally not installed.

The image also includes CPU-only `torch`, `torchvision`, and `umap-learn` for
the Brain similarity and visualization workflows.

## Networking

FiftyOne is exposed through the shared Louis Gateway:

```text
https://fiftyone.inspection.alpha.canada.ca
```

The HTTPRoute is defined in `apps/annotation/base/httproute.yaml`. The Gateway
listener is defined in `apps/louis/base/gateway.yaml`.

## Dataset Storage

FiftyOne should load media from filesystem paths visible inside the pod. The
shared annotation CephFS workspace is mounted at:

```text
/datasets
/ailab
```

Use `/datasets` for new FiftyOne imports. `/ailab` is kept for compatibility
with the existing shared annotation workspace.

Recommended dataset layouts:

```text
/datasets/incoming/<date>/<batch>/
  Ambrosia artemisiifolia/
    image001.jpg
  Avena fatua/
    image002.jpg
```

```text
/datasets/coco/<date>/<batch>/
  data/
    image001.jpg
  labels.json
```

S3-compatible storage such as MinIO or Ceph RGW should be treated as durable
object storage. When datasets arrive there first, sync the selected prefix into
the CephFS-backed `/datasets` workspace before importing it into FiftyOne.

## S3 Sync

The `fiftyone-s3-sync` CronJob mirrors datasets from the MLflow S3-compatible
store into the shared `/datasets` workspace.

Default source and destination:

```text
s3://mlflow/datasets -> /datasets/s3-imports
```

The CronJob is suspended by default. It does not run on a schedule. Use the
manual GitHub Actions workflow `FiftyOne S3 dataset sync` to trigger a sync
when a new dataset prefix is ready.

The CronJob is guarded with `concurrencyPolicy: Forbid`, `backoffLimit: 1`,
and a 30-minute deadline so failed or slow syncs do not overlap indefinitely.

A cluster operator can also create a one-off Job from the CronJob template:

```bash
kubectl create job -n annotation --from=cronjob/fiftyone-s3-sync \
  fiftyone-s3-sync-manual
kubectl wait -n annotation --for=condition=complete \
  job/fiftyone-s3-sync-manual --timeout=30m
```

The job uses `fiftyone-s3-secrets`, sourced from the same Vault path as the
MLflow S3 configuration. Do not put S3 credentials in Git.

Live sync checks:

```bash
kubectl get externalsecret fiftyone-s3-secrets -n annotation
kubectl get secret fiftyone-s3-secrets -n annotation
kubectl get cronjob fiftyone-s3-sync -n annotation
kubectl logs job/fiftyone-s3-sync-manual -n annotation
kubectl exec deploy/fiftyone -n annotation -- ls -la /datasets/s3-imports
```

## User Workflow

1. Add or sync a dataset into `/datasets`.
2. Open FiftyOne.
3. Use the IO plugin to import the dataset from `/datasets`.
4. Review images, labels, boxes, tags, and saved views.
5. Export curated labels or manifests back to the shared workspace.
6. Sync curated outputs to S3 or MLflow artifacts when needed.

## Validation

Basic deployment checks:

```bash
kubectl get pods,svc,pvc -n annotation
kubectl get httproute -n annotation
kubectl logs deploy/fiftyone -n annotation
kubectl exec deploy/fiftyone -n annotation -- ls -la /datasets
```

Plugin check:

```bash
kubectl exec deploy/fiftyone -n annotation -- fiftyone plugins list
```

Expected plugins:

```text
@voxel51/annotation
@voxel51/io
@voxel51/brain
@voxel51/utils
```

Persistence check:

```bash
kubectl rollout restart deploy/fiftyone -n annotation
kubectl rollout status deploy/fiftyone -n annotation
```

After restart, confirm previously imported datasets are still listed in the
FiftyOne UI.

## Smoke Test

Use a small class-folder or COCO dataset under `/datasets` to validate imports.

Class-folder import should preserve species names from folder names.
COCO import should render bounding boxes in the sample viewer.

For a repeatable local version of this validation, use:

```text
/Users/youssefjedidi/CFIA/fiftyone-validation-lab
```
