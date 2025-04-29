# Gateway configuration

See `grafana-lgtm/base` to find the gateway and httproute configuration of the monitoring namespace.

## Grafana LGTM Stack - Component Overview

This document provides a summary of the observability tools included in a full LGTM stack (Loki, Grafana, Tempo, Mimir) deployed via Helm.

---

### Grafana Alloy

Grafana Alloy (formerly Grafana Agent) acts as a unified telemetry collector. It receives logs, metrics, and traces via OTLP (gRPC/HTTP), processes them in batches, and forwards them to Mimir, Loki, and Tempo. It can be deployed as a DaemonSet for cluster-wide collection, and mounts host paths like `/var/log` and Docker container logs.

---

### Grafana

Grafana is the visualization and query interface for the entire stack. It is configured to connect to Mimir for metrics, Loki for logs, and Tempo for traces. It supports dashboards, service maps, and features like trace-to-log or trace-to-metrics correlation. Grafana is deployed with persistent storage and may be exposed through TLS-enabled Ingress.

---

### Loki

Loki is the log aggregation system designed to work like Prometheus but for logs. It indexes log streams based on labels and allows efficient querying via LogQL. The distributed Loki setup includes:

- **Distributor**: Receives log entries and pushes them to ingesters.
- **Ingester**: Writes logs to long-term storage.
- **Querier**: Handles log queries.
- **Compactor**: Compacts index and chunks to optimize storage.
- **Ruler**: Evaluates alerting rules on logs and sends alerts to Alertmanager.
- **Index Gateway**: Accelerates log index access in distributed environments.

Each of these components uses persistent volumes (e.g., Ceph) for durability.

---

### Mimir

Mimir is a scalable, long-term storage backend for Prometheus-compatible metrics. It supports multi-tenant operations and object storage backends (like S3 or MinIO). Key components include:

- **Distributor**: Handles incoming metrics.
- **Ingester**: Temporarily stores and replicates metrics.
- **Querier/Query Frontend**: Serve and optimize PromQL queries.
- **Ruler**: Evaluates alerting and recording rules.
- **Compactor/Store Gateway**: Manage long-term metric blocks.
- **Alertmanager**: Receives alerts from rulers and routes them to email, Slack, etc.

Mimir is deployed with persistent volumes and supports zone-aware replication.

---

### Tempo

Tempo is a distributed tracing backend designed to ingest, store, and query trace data at scale. It integrates with tracing protocols such
as OTLP, Jaeger, Zipkin, and OpenCensus, and enables correlation between traces, logs, and metrics within Grafana.

The distributed Tempo setup includes:

- **Distributor**: Receives trace spans and forwards them to ingesters.
- **Ingester**: Buffers and writes trace data to long-term storage. In this setup, trace data is stored locally on persistent volumes (e.g., Ceph).
- **Querier**: Handles trace search and retrieval operations.
- **Query Frontend**: Optimizes and parallelizes complex trace queries.
- **Compactor**: Manages trace block retention and performs compaction for storage efficiency.
- **Receivers**: Supports multiple ingestion protocols including OTLP (gRPC/HTTP), Jaeger (gRPC/Thrift), and OpenCensus.

---

### Grafana OnCall (optional)

Grafana OnCall is an on-call management system designed to integrate with Grafana alerts. It handles alert grouping, escalation policies, and on-call scheduling. Though optional in this deployment, it can enhance alert response workflows.

## Kubernetes metrics and dashboard

### Kubernetes Dashboard

The Kubernetes Dashboard is a web-based UI that allows users to interact with Kubernetes objects visually. While it is not part of the LGTM stack, it complements it by offering a high-level overview of cluster resources and events.

Use cases include:

- Browsing workloads, services, and volumes
- Viewing pod logs and events
- Manually applying YAML manifests

---

### metrics-server

`metrics-server` provides real-time resource usage metrics (CPU, memory) to the Kubernetes control plane. It is used by:

Example usage:

```sh
kubectl top nodes
kubectl top pods
```

### kube-state-metrics

`kube-state-metrics` is a service that exposes the state of Kubernetes resources (Deployments, Pods, Nodes, etc.) as Prometheus metrics. Unlike `metrics-server`, it focuses on declarative object state rather than real-time resource usage.
