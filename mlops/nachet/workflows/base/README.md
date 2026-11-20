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
