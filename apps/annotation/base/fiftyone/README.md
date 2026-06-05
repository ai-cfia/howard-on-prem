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
