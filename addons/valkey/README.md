# Valkey

[Valkey](https://valkey.io) is an open source, high performance, in-memory data structure store, used as a database, cache, message broker and streaming engine.

This chart renders a single `ValkeyCluster` custom resource (`valkey.io/v1alpha1`) that is reconciled by the cluster-scoped **Valkey Operator**.

## Architecture

Unlike the bitnami-derived addons in this repository, Valkey follows an operator + CRD model:

```
[control plane] charts/classes/files/valkey.yaml
      → Crossplane XRD + Composition + AddonClass (generated)
      → helm Release pulls charts/addons/valkey  (this chart)
            → renders one ValkeyCluster CR
                  → Valkey Operator reconciles it into pods/PVCs
```

## Prerequisites: install the Valkey Operator

The Valkey Operator and its CRDs (`valkeyclusters.valkey.io`, `valkeynodes.valkey.io`) are
cluster-level singletons. They must be installed **before** any `ValkeyCluster` is created,
and they are **not** bundled in this chart.

### Requirements

- Kubernetes >= 1.20
- Cluster-admin access (operator installs `ClusterRole`, `ClusterRoleBinding`, CustomResourceDefinitions)

### Installation

```bash
helm install valkey-operator valkey-operator \
  --repo https://valkey.io/valkey-helm/ \
  --version 0.1.1 \
  --namespace valkey-system --create-namespace
```

### What this installs

- Chart: `valkey-operator` (repo `https://valkey.io/valkey-helm/`)
- Image: `ghcr.io/valkey-io/valkey-operator:v0.1.0`
- RBAC: `ServiceAccount` + `ClusterRole`/`ClusterRoleBinding` (all-namespaces watch) + `Role` for leader election
- CRDs (`valkeyclusters`, `valkeynodes`) live in the operator chart's `crds/` directory and are applied automatically on install.

### Verification

```bash
kubectl get pods -n valkey-system
# Expect one valkey-operator-controller-manager pod with READY 1/1

kubectl get crd | grep valkey.io
# Expect valkeyclusters.valkey.io and valkeynodes.valkey.io
```

### CRD upgrade caveat

Helm does not upgrade or delete resources in `crds/` on `helm upgrade`/`helm uninstall`.
When bumping the operator version, apply CRDs explicitly:

```bash
kubectl replace -f https://raw.githubusercontent.com/valkey-io/valkey-helm/<TAG>/valkey-operator/crds/valkey.io_valkeyclusters.yaml
kubectl replace -f https://raw.githubusercontent.com/valkey-io/valkey-helm/<TAG>/valkey-operator/crds/valkey.io_valkeynodes.yaml
```

### One operator per cluster

Only one Valkey Operator instance should be running per cluster (leader election handles HA).
Multiple installations will conflict via `ClusterRole` and CRD ownership.

## Parameters

Top-level values map directly to `ValkeyCluster.spec`.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `imagePullPolicy` | Image pull policy | `IfNotPresent` |
| `shards` | Number of shard groups (min 1) | `1` |
| `replicas` | Replicas per shard group (min 0) | `2` |
| `workloadType` | `StatefulSet` or `Deployment` (immutable) | `StatefulSet` |
| `config` | Additional Valkey config (map) | `{}` |
| `persistence.enabled` | Render the persistence block | `true` |
| `persistence.size` | PVC size (expand-only) | `1Gi` |
| `persistence.storageClassName` | StorageClass (immutable) | `""` |
| `persistence.reclaimPolicy` | `Retain` or `Delete` | `Retain` |
| `resources` | Valkey container resources | `{}` |
| `exporter.enabled` | Metrics exporter sidecar | `true` |
| `exporter.resources` | Exporter resources | `{}` |
| `tls.enabled` | Enable TLS (TLS-only mode; self-signed cert generated) | `false` |
| `tls.certValidityDays` | Validity period (days) for the generated CA and certificate | `36500` |
| `users` | ACL user specs (array) | `[]` |
| `nodeSelector` | Pod nodeSelector | `{}` |

## Constraints enforced by the CRD

- `persistence` requires `workloadType: StatefulSet`.
- `persistence` cannot be added or removed after creation; `size` may only be expanded; `storageClassName` is immutable.
- `workloadType` is immutable after creation.

## TLS

TLS is disabled by default. When enabled (`tls.enabled=true`), the chart generates a self-signed
CA and certificate and creates a `kubernetes.io/tls` secret named `<release-name>-valkey-tls`
(namespace scoped) containing `ca.crt`, `tls.crt` and `tls.key`. The `ValkeyCluster` always
references this fixed secret name.

Enabling TLS puts the cluster in TLS-only mode: the operator sets `port 0` and `tls-port 6379`,
so plaintext clients can no longer connect.

The certificate SANs cover the operator's service naming:

- `valkey-<release-name>` and its FQDNs (`*.valkey-<release-name>.<namespace>.svc.cluster.local`)

where the operator creates the cluster headless service as `valkey-<clusterName>` and per-node
workloads as `valkey-<clusterName>-<shard>-<node>`.

On `helm upgrade` an existing secret is preserved via `lookup`, so certificates remain stable
across upgrades. To disable TLS, set `tls.enabled=false`.
