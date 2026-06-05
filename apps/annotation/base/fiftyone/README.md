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
Open-source FiftyOne should be treated as filesystem-backed for media, so the
active review workspace is exposed through CephFS rather than direct `s3://`
paths.

The pod mounts the annotation shared CephFS PVC at:

```text
/datasets
/ailab
```

`/datasets` is the preferred path to use in the FiftyOne IO plugin when loading
seed image folders. `/ailab` is kept for compatibility with the shared
annotation workspace pattern used by Label Studio and AI Lab shared work
containers.

Recommended workflow:

```text
1. Add a seed dataset to the shared workspace, or sync it there from S3/MinIO.
2. Open FiftyOne.
3. Use the IO plugin to import from /datasets.
4. Review labels, boxes, tags, and saved views.
5. Export curated labels/manifests back to the shared workspace.
6. Sync curated outputs to S3/MLflow artifacts when needed.
```

Class-folder example:

```text
/datasets/incoming/2026-06-05/batch-001/
  Ambrosia artemisiifolia/
    image001.jpg
  Avena fatua/
    image002.jpg
```

COCO example:

```text
/datasets/coco/2026-06-05/batch-001/
  data/
    image001.jpg
  labels.json
```

S3-compatible storage such as MinIO/Ceph RGW should be treated as durable
object/artifact storage. If a dataset lands in S3 first, sync the selected
prefix into the CephFS-backed `/datasets` workspace before importing it into
FiftyOne.

## Validation

```bash
kubectl get httproute -n annotation
kubectl get pods,svc,pvc -n annotation
kubectl get pods,svc,statefulset,pvc -n mongodb
kubectl logs deploy/fiftyone -n annotation
kubectl logs statefulset/mongodb -n mongodb
kubectl rollout restart deploy/fiftyone -n annotation
kubectl port-forward svc/fiftyone 5151:5151 -n annotation
kubectl exec deploy/fiftyone -n annotation -- ls /datasets
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

Shared dataset workspace validation:

1. Confirm the shared workspace is mounted:

   ```bash
   kubectl exec deploy/fiftyone -n annotation -- ls -la /datasets
   ```

2. Create a tiny class-folder smoke dataset from the FiftyOne pod terminal:

   ```bash
   kubectl exec deploy/fiftyone -n annotation -- python - <<'PY'
   from pathlib import Path
   from PIL import Image, ImageDraw

   root = Path("/datasets/fiftyone-smoke/class-folders")
   species = root / "Ambrosia artemisiifolia"
   species.mkdir(parents=True, exist_ok=True)

   image = Image.new("RGB", (320, 240), "#202428")
   draw = ImageDraw.Draw(image)
   draw.ellipse((80, 70, 240, 170), fill="#b99b55", outline="#f6e6a8", width=6)
   image.save(species / "seed-001.jpg")
   PY
   ```

3. Import the class-folder dataset:

   ```bash
   kubectl exec deploy/fiftyone -n annotation -- python - <<'PY'
   import fiftyone as fo

   name = "fiftyone-shared-storage-class-smoke"
   if fo.dataset_exists(name):
       fo.delete_dataset(name)

   dataset = fo.Dataset.from_dir(
       dataset_dir="/datasets/fiftyone-smoke/class-folders",
       dataset_type=fo.types.ImageClassificationDirectoryTree,
       name=name,
   )
   dataset.persistent = True
   print(dataset.name, len(dataset), dataset.distinct("ground_truth.label"))
   PY
   ```

4. Create and import a tiny COCO smoke dataset:

   ```bash
   kubectl exec deploy/fiftyone -n annotation -- python - <<'PY'
   import json
   from pathlib import Path
   from PIL import Image, ImageDraw
   import fiftyone as fo

   root = Path("/datasets/fiftyone-smoke/coco")
   data = root / "data"
   data.mkdir(parents=True, exist_ok=True)

   image = Image.new("RGB", (320, 240), "#202428")
   draw = ImageDraw.Draw(image)
   draw.ellipse((80, 70, 240, 170), fill="#b99b55", outline="#f6e6a8", width=6)
   image.save(data / "seed-001.jpg")

   labels = {
       "images": [
           {"id": 1, "file_name": "seed-001.jpg", "width": 320, "height": 240}
       ],
       "annotations": [
           {
               "id": 1,
               "image_id": 1,
               "category_id": 1,
               "bbox": [80, 70, 160, 100],
               "area": 16000,
               "iscrowd": 0,
           }
       ],
       "categories": [{"id": 1, "name": "Ambrosia artemisiifolia"}],
   }
   (root / "labels.json").write_text(json.dumps(labels), encoding="utf-8")

   name = "fiftyone-shared-storage-coco-smoke"
   if fo.dataset_exists(name):
       fo.delete_dataset(name)

   dataset = fo.Dataset.from_dir(
       dataset_type=fo.types.COCODetectionDataset,
       data_path=str(data),
       labels_path=str(root / "labels.json"),
       name=name,
   )
   dataset.persistent = True

   detections_field = next(
       name
       for name, field in dataset.get_field_schema().items()
       if getattr(field, "document_type", None) is fo.Detections
   )
   print(
       dataset.name,
       len(dataset),
       detections_field,
       dataset.count(f"{detections_field}.detections"),
   )
   PY
   ```

5. Restart FiftyOne and confirm both datasets still exist:

   ```bash
   kubectl rollout restart deploy/fiftyone -n annotation
   kubectl rollout status deploy/fiftyone -n annotation
   kubectl exec deploy/fiftyone -n annotation -- python - <<'PY'
   import fiftyone as fo

   for name in (
       "fiftyone-shared-storage-class-smoke",
       "fiftyone-shared-storage-coco-smoke",
   ):
       dataset = fo.load_dataset(name)
       print(name, len(dataset), dataset.persistent)
   PY
   ```
