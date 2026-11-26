# Nachet dataset release smoke test

The `cloudnativepg` Argo CD application provisions the shared `mlops-test`
database and `mlops-test-user` login in the `acia-cfia-dev-cluster` PostgreSQL
cluster. The `nachet-mlops` application syncs the workflow credentials into
`argo-workflows`. Each smoke run uses a schema named after its workflow UUID.

## Vault setup

Create an entry in the `devsecops` Vault KV mount at
`cloudnativepg/mlops-test-user` with these fields.

| Field | Value |
| --- | --- |
| `username` | `mlops-test-user` |
| `password` | A generated password for this role |
| `DATASET_DATABASE_URL` | `postgresql+psycopg://mlops-test-user:<url-encoded-password>@acia-cfia-dev-cluster-rw.cloudnativepg.svc.cluster.local:5432/mlops-test` |

Use the same password in both fields, with percent encoding in the URL. Update
both fields in the same Vault edit when rotating the password.

The workflow ExternalSecret reads the existing `nachet/mlops/smoke` entry in the
`secrets` mount and maps the Vault fields to the workflow environment.

| Vault field | Workflow environment variable |
| --- | --- |
| `AWS_ENDPOINT_URL_S3` | `S3_ENDPOINT_URL` |
| `AWS_ACCESS_KEY_ID` | `S3_ACCESS_KEY` |
| `AWS_SECRET_ACCESS_KEY` | `S3_SECRET_KEY` |
| `AWS_DEFAULT_REGION` | `AWS_DEFAULT_REGION` |
| `TEST_ROOT_DIR` | `DATASET_SMOKE_ROOT` |

`AWS_ENDPOINT_URL_S3` should point to the Ceph object gateway for the smoke
bucket. For the cold gateway, see the Nachet preparation config preparation-config.yaml.

## First run

Once the manifests are available to Argo CD, sync `nachet-mlops`. The
`cloudnativepg` application syncs automatically. Check database provisioning and
secret sync. The Secret description lists the keys and sizes.

```sh
kubectl -n cloudnativepg wait --for=condition=Ready externalsecret/mlops-test-user-creds --timeout=120s
kubectl -n cloudnativepg wait --for=jsonpath='{.status.applied}'=true database/mlops-test --timeout=120s
kubectl -n argo-workflows wait --for=condition=Ready externalsecret/nachet-dataset-release-smoke --timeout=120s
kubectl -n argo-workflows describe secret nachet-dataset-release-smoke
```

Use the Nachet WorkflowTemplate and dataset-release image with per-run schema
and object prefix support. The seed pod creates and migrates each schema. The
exit handler drops the schema and deletes the run's fixture objects.

For Howard, set `TEST_ROOT_DIR` to `nachet-seed-image-dataset/smoke` in Vault.
Leave the workflow's `container` parameter blank to use that bucket. Each run
uses `smoke/<workflow UUID>/`. The Vault S3 credentials need read, write, and
delete access under `smoke/`. To use a dedicated bucket, set `container` to
`nachet-dataset-smoke` or `nachet-dataset-smoke-<suffix>`.

```sh
argo submit -n argo-workflows --from workflowtemplate/nachet-dataset-release-smoke --watch
```

## Publish a normal dataset release

The `nachet_dataset_releases` database runs on `acia-cfia-dev-cluster`. The
default schema is `nachet_datasets`. Create these Vault entries before syncing
the CloudNativePG and Nachet workflow manifests.

| Vault mount and path | Required fields |
| --- | --- |
| `devsecops/cloudnativepg/nachet-release-publisher` | `username` (`nachet-release-publisher`), `password`, and `DATASET_DATABASE_URL` |
| `devsecops/cloudnativepg/nachet-release-reader` | `username` (`nachet-release-reader`) and `password` |
| `secrets/nachet/mlops/dataset-release` | `S3_ENDPOINT_URL`, `S3_ACCESS_KEY`, `S3_SECRET_KEY`, and any needed region setting |

Use `acia-cfia-dev-cluster-rw.cloudnativepg.svc.cluster.local:5432` and
`nachet_dataset_releases` in both PostgreSQL URLs. Percent-encode passwords
in the URLs. Store the reader URL in the training Vault entry below. Give the
publisher S3 identity read access to `png/detection/` and read/write access to
`png/classification/` in `nachet-seed-image-dataset`.

After the database is ready, connect to it as the publisher and run
`CREATE SCHEMA IF NOT EXISTS nachet_datasets;`. Apply the standalone Nachet
dataset migrations from `mlops/datasets` in Nachet. Set
`DATASET_DATABASE_URL` in the migration environment to the publisher URL from
Vault, then run `uv run alembic -c alembic.ini upgrade head`. Grant the reader
access to the created tables and restrict default database access:

```sql
REVOKE CONNECT, TEMPORARY ON DATABASE nachet_dataset_releases FROM PUBLIC;
GRANT CONNECT ON DATABASE nachet_dataset_releases TO "nachet-release-reader";
GRANT USAGE ON SCHEMA nachet_datasets TO "nachet-release-reader";
GRANT SELECT ON nachet_datasets.dataset_release,
                nachet_datasets.dataset_membership,
                nachet_datasets.dataset_crop TO "nachet-release-reader";
```

Prepare the draft using the publisher connection. Submit
`nachet-dataset-release` with that draft's name and version and
`container=nachet-seed-image-dataset`.

## Train on a reviewed dataset release

Create a dedicated entry at `nachet/mlops/training/dataset-release` in the
`secrets` Vault KV mount. The `nachet-training-dataset-release` ExternalSecret
copies the fields from this entry into `argo-workflows`. Keep the entry limited
to the training dataset settings below.

| Vault field | Value |
| --- | --- |
| `DATASET_DATABASE_URL` | `postgresql+psycopg://` URL for a dedicated read-only login on the release registry database. Percent-encode the password in the URL. |
| `S3_ENDPOINT_URL` | Ceph object gateway for the published release bucket. |
| `S3_ACCESS_KEY` | Access key for the training dataset reader. |
| `S3_SECRET_KEY` | Secret key for the training dataset reader. |
| `DATASET_REGISTRY_SCHEMA` | Optional registry schema. Defaults to `nachet_datasets`. |
| `DATASET_CONTAINER` | Optional default release bucket. The workflow's `dataset-container` parameter can select a bucket. |
| `S3_REGION_NAME` | Optional region for the release bucket's gateway. |

Use the database and schema that contain the ready release. Grant the login
database `CONNECT`, schema `USAGE`, and table `SELECT` on `dataset_release`,
`dataset_membership`, and `dataset_crop`. Grant the Ceph identity
`s3:GetObject` on the selected bucket's `releases/`, `png/detection/`, and
`png/classification/` prefixes. These credentials serve only the dataset
reader. MLflow artifact access uses the existing `nachet-training-s3` Secret.

After the Howard change is merged, sync `nachet-mlops` and check readiness and
key names.

```sh
kubectl -n argo-workflows wait --for=condition=Ready externalsecret/nachet-training-dataset-release --timeout=120s
kubectl -n argo-workflows describe secret nachet-training-dataset-release
```

After the Nachet training change is merged, wait for the post-merge
[MLOps training build and publish workflow](https://github.com/ai-cfia/nachet/actions/workflows/mlops-training-build.yml)
to publish both `nachet-detector-trainer:main` and
`nachet-classifier-trainer:main` before submitting training.

Run `nachet-detector-training` and `nachet-classifier-training` with the
`smoke` profile and the same dataset name, version, and expected manifest
SHA-256. Select a ready release with published classification crops. Check
that both CPU preflights pass and that the MLflow runs record the same
release identity. Submit each workflow again with a different manifest hash
and confirm that the CPU preflight fails before Argo creates a GPU pod.
