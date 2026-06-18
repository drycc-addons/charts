# Generic Addon

Deploys any container image as a StatefulSet with optional Service and PVC.
No operator required — renders native Kubernetes resources directly.

## Usage

Provisioned via the drycc addons control plane:

```
drycc addons create generic <name> --plan <plan> --set image.repository=<repo> --set image.tag=<tag>
```

## Configuration

| Parameter | Description | Default |
|---|---|---|
| `image.repository` | Container image repository | `""` |
| `image.tag` | Container image tag | `""` |
| `replicas` | Number of pod replicas (1–7) | `1` |
| `command` | Override container entrypoint | `[]` |
| `args` | Override container arguments | `[]` |
| `env` | Environment variables (key-value map) | `{}` |
| `ports` | Container ports to expose | `[]` |
| `service.ports` | Service port definitions | see values.yaml |
| `persistence.enabled` | Create a volumeClaimTemplate | `false` |
| `persistence.size` | PVC size | `1Gi` |
| `persistence.mountPath` | Mount path inside container | `/data` |
| `healthCheck` | Liveness/readiness probes | `{}` |
| `resources` | CPU/memory limits and requests | `{}` |
| `nodeSelector` | Node labels for scheduling | `{}` |

## Plans

| Plan | CPU | Memory | Replicas (default) | Persistence |
|---|---|---|---|---|
| micro | 250m | 512Mi | 1 | none |
| small | 500m | 1Gi | 1 | 4Gi |
| medium | 1 | 2Gi | 2 | 8Gi |
| large | 2 | 4Gi | 3 | 20Gi |
| xlarge | 4 | 8Gi | 5 | 50Gi |
| 2xlarge | 8 | 16Gi | 5 | 100Gi |

Plan resources are **per-pod** limits. Replicas are user-adjustable (1–7).
