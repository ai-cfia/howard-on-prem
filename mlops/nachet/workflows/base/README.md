# Nachet dataset release smoke test

The `cloudnativepg` Argo CD application provisions the
`nachet-dataset-release-smoke` database and the `nachet_datasets_smoke` schema in
the existing `acia-cfia-dev-cluster` PostgreSQL cluster. The `nachet-mlops`
application syncs the workflow credentials into `argo-workflows`.

## Vault setup

Create an entry in the `devsecops` Vault KV mount at
`cloudnativepg/nachet-dataset-release-smoke-user` with these fields.

| Field | Value |
| --- | --- |
| `username` | `nachet_dataset_smoke` |
| `password` | A generated password for this role |
| `DATASET_DATABASE_URL` | `postgresql+psycopg://nachet_dataset_smoke:<url-encoded-password>@acia-cfia-dev-cluster-rw.cloudnativepg.svc.cluster.local:5432/nachet-dataset-release-smoke` |
| `DATASET_REGISTRY_SCHEMA` | `nachet_datasets_smoke` |

Use the same password in both fields, with percent encoding in the URL. Update
both fields in the same Vault edit when rotating the password. The workflow
ExternalSecret also reads `S3_ENDPOINT_URL`, `S3_ACCESS_KEY`, and `S3_SECRET_KEY`
from `nachet/mlops/smoke` in the `secrets` mount.

## First run

Once the manifests are available to Argo CD, sync `nachet-mlops`. The
`cloudnativepg` application syncs automatically. Check database provisioning and
secret sync. The Secret description lists the keys and sizes.

```sh
kubectl -n cloudnativepg wait --for=condition=Ready externalsecret/nachet-dataset-release-smoke-user-creds --timeout=120s
kubectl -n cloudnativepg wait --for=jsonpath='{.status.applied}'=true database/nachet-dataset-release-smoke --timeout=120s
kubectl -n argo-workflows wait --for=condition=Ready externalsecret/nachet-dataset-release-smoke --timeout=120s
kubectl -n argo-workflows describe secret nachet-dataset-release-smoke
```

Run the standalone migrations from the Nachet checkout's `mlops/datasets`
directory in an environment with access to the PostgreSQL service. Supply
`DATASET_DATABASE_URL` and `DATASET_REGISTRY_SCHEMA` from the smoke entry.
From a workstation with cluster access, run
`kubectl -n cloudnativepg port-forward svc/acia-cfia-dev-cluster-rw 15432:5432`
in another terminal and use `127.0.0.1:15432` in the URL for the migration shell.

```sh
uv sync --locked
uv run alembic -c alembic.ini upgrade head
uv run alembic -c alembic.ini current
```

Submit the smoke workflow with the dedicated Ceph bucket. Use the actual bucket
name if it has a suffix. The workflow accepts `nachet-dataset-smoke` and
`nachet-dataset-smoke-<suffix>`.

```sh
argo submit -n argo-workflows --from workflowtemplate/nachet-dataset-release-smoke -p container=nachet-dataset-smoke --watch
```
