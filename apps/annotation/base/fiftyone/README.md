# FiftyOne

This directory deploys FiftyOne as an internal ML dataset curation and visual
review workbench.

## Scope

- The FiftyOne app runs as a single-replica Deployment.
- The deployed image extends the pinned upstream FiftyOne image and installs
  the AI Lab's required FiftyOne plugins.
- MongoDB is deployed as a shared storage service from `storage/mongodb` and
  stores FiftyOne metadata.
- This first pass intentionally skips MongoDB backups, clustering, and
  hardening so the team can validate the app, database connection, and
  persistence.
- Access control is limited to the existing cluster/network controls for this
  first pass.

## Plugins

The custom FiftyOne image is built from:

```text
voxel51/fiftyone:1.15.0-python3.9-20260502
```

and installs the following plugins from the pinned `voxel51/fiftyone-plugins`
ref in the DevOps Dockerfile:

```text
@voxel51/annotation
@voxel51/io
@voxel51/brain
@voxel51/utils
```

Delegation is intentionally not installed for this phase.

Built-in vs installed behavior:

- `@voxel51/operators` and `@voxel51/panels` are already built into the
  upstream FiftyOne image.
- `@voxel51/annotation`, `@voxel51/io`, `@voxel51/brain`, and
  `@voxel51/utils` are installed into `/opt/fiftyone/plugins` by the custom
  image build.
- `FIFTYONE_PLUGINS_DIR` is set to `/opt/fiftyone/plugins` in the deployment so
  FiftyOne loads the installed plugins from the image.

The image also installs CPU-only `torch`, `torchvision`, and `umap-learn`. The
Brain plugin can use precomputed embeddings without Torch, but the UI's
model-based similarity workflow loads FiftyOne Model Zoo models such as
`resnet18-imagenet-torch`, which require Torch at runtime. The Brain
visualization workflow uses UMAP by default, which requires `umap-learn`.

The image build is owned by the `ai-cfia/devops` repository under
`dockerfiles/fiftyone`. This deployment only consumes the published image.

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

The deployment mounts a dedicated CephFS shared filesystem PVC for datasets:

```text
/datasets
```

The dataset PVC uses the `ceph-cold-filesystem` storage class with
`ReadWriteMany`, matching the existing Rook/CephFS shared filesystem pattern in
Howard. This keeps the first storage pass simple: files are made available on a
normal filesystem path, and FiftyOne imports them from there.

The pod also mounts the annotation shared PVC at `/ailab`, matching the shared
workspace pattern used by Label Studio and the AI Lab shared work containers.

Recommended import paths:

```text
/datasets
/ailab
```

For seed class-folder datasets, keep species names in folder names:

```text
/datasets/Ambrosia artemisiifolia/
  image001.jpg
```

For COCO detection datasets:

```text
/datasets/<batch>/
  data/
    image001.jpg
  labels.json
```

## Validation

### Cold Ceph S3 mounts

FiftyOne reads two prefixes in `nachet-seed-image-dataset`:

| Cold bucket prefix | Read-only path in FiftyOne |
| --- | --- |
| `datasets/` | `/fiftyone-s3` |
| `png/detection/` | `/fiftyone-preparation/png/detection` |

FiftyOne keeps the full image paths in its review records. Keep the same paths
when moving the objects to cold Ceph.

Both Argo CD applications auto-sync. Merging the Howard change deploys the
mount and configuration changes. Complete the image-copy and credential checks
in this section before merging.

1. Let active preparation runs finish and pause new runs. Inventory the files
   served by `/fiftyone-s3` and `/fiftyone-preparation`. Identify any jobs or
   tools uploading to the hot prefixes and stop them or switch their upload
   destinations during the cutover. Copy the dataset files under
   `s3://mlflow/datasets/` and the referenced PNGs under
   `s3://mlflow/png/detection/` to the same prefixes in the cold bucket. Use the
   hot gateway for the source and the cold gateway for the destination. Verify
   that the cold objects match the originals before switching the mounts.
2. Add `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` to
   `secrets/nachet/preparation/cold-s3-readonly` in Vault. Both mounts use the
   resulting `fiftyone-cold-s3` Secret. Grant the reader `s3:ListBucket` for
   `datasets`, `datasets/*`, `png/detection` and `png/detection/*`, and
   `s3:GetObject` under both prefixes. Test both s3fs mounts with the reader
   account, including opening an image through each mount.
3. Merge the Howard change for
   [#469](https://github.com/ai-cfia/howard-on-prem/issues/469) and wait for
   Argo CD's `annotation` and `nachet-mlops` applications to sync successfully
   and become healthy. Then merge Nachet's preparation-template change.
   Open an existing image from each mount that has saved samples. Run a small
   batch through Argo and open a newly prepared image in FiftyOne. Then resume
   normal preparation.

If rolling the mounts back to hot Ceph after new cold uploads, first verify
that every referenced image also exists in hot storage. Copy and verify any
missing images before reverting, and coordinate the upload destinations again.

### Preparation workflow permissions

Argo uses `nachet-preparation-cold-s3`, supplied from Vault at
`secrets/nachet/preparation/cold-s3`. Store the credentials of
`nachet-seed-image-dataset-user` there. Its cold bucket policy grants
`s3:ListBucket` under `raw/`, `s3:GetObject` under `raw/*`, and
`s3:GetObject` and `s3:PutObject` under `png/detection/*`. The policy was
applied through Ceph on November 16. Effective workflow access needs testing.

Confirm and record the bucket owner and ACL grants in the cold Ceph dashboard
before using those credentials. An Allow-only bucket policy
does not remove permissions the workflow user already has through ownership
or ACL grants. Check the actual permissions with the workflow account.

With the workflow account, list a collection under `raw/`, read an original,
and write and read back a disposable PNG under `png/detection/`. Check that a
write to a fresh disposable key under `raw/` returns `AccessDenied`. If that
write succeeds, have the bucket owner remove the probe and correct the policy
before running preparation. COCO files are written to the shared workspace PVC.

### Cluster checks

```bash
kubectl get httproute -n annotation
kubectl get pods,svc,pvc -n annotation
kubectl get pods,svc,statefulset,pvc -n mongodb
kubectl logs deploy/fiftyone -n annotation
kubectl exec deploy/fiftyone -n annotation -- ls -la /datasets
kubectl logs statefulset/mongodb -n mongodb
kubectl rollout restart deploy/fiftyone -n annotation
kubectl port-forward svc/fiftyone 5151:5151 -n annotation
```

Plugin checks:

```bash
kubectl exec deploy/fiftyone -n annotation -- fiftyone plugins list
```

Expected installed plugins:

```text
@voxel51/annotation
@voxel51/io
@voxel51/brain
@voxel51/utils
```

Expected excluded plugin:

```text
@voxel51/delegation
```

should not be listed.

Local validation of the custom image:

- Docker image built successfully.
- `fiftyone plugins list` showed all four requested plugins enabled.
- CPU-only `torch` and `torchvision` imported successfully.
- `umap-learn` imported successfully.
- Brain model-based similarity ran successfully with
  `resnet18-imagenet-torch` on a local smoke-test dataset.
- Brain visualization ran successfully with precomputed embeddings on a local
  smoke-test dataset.
- A local FiftyOne container started successfully against MongoDB and returned
  HTTP 200.
- Brain duplicate/similarity workflows were previously validated in the local
  validation lab on a sample seed dataset:
  - exact duplicates: pass
  - similarity: pass
  - visualization: pass
  - uniqueness: pass
  - COCO similarity: pass

Manual checks:

- Open `https://fiftyone.inspection.alpha.canada.ca`.
- Confirm the UI loads.
- Import or attach a small test dataset if appropriate.
- Restart the FiftyOne pod.
- Confirm dataset metadata remains available after restart.
- Restart the MongoDB pod and confirm metadata persists from the StatefulSet
  volume claim.
