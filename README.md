# Charts

Helm charts for the drycc addons platform. Two-layer data-driven model powered by Crossplane.

## Structure

```
charts/
├── addons/                    # Per-instance addon charts (OCI distribution)
│   └── valkey/                #   → renders one ValkeyCluster CR
│
├── classes/                   # Crossplane control plane configuration
│   ├── Chart.yaml
│   ├── crds/                  #   Platform-owned CRDs (AddonClass)
│   ├── files/                 #   Addon definitions (one .yaml per addon)
│   │   └── valkey.yaml        #     → drives XRD + Composition + AddonClass generation
│   ├── templates/
│   │   ├── definitions.yaml   #     CompositeResourceDefinition (Glob loop)
│   │   ├── compositions.yaml  #     Composition (Glob loop)
│   │   ├── addonclasses.yaml  #     AddonClass (Glob loop)
│   │   └── providerconfig.yaml#     Helm ProviderConfig
│   └── README.md
│
├── .AGENTS.md                 # Agent instructions for migrating new operators
├── LICENSE
├── Makefile
└── README.md
```

## addons/

Per-instance addon charts. Each chart renders a single Kubernetes resource (a CR, a
StatefulSet, etc.) and is consumed by the Crossplane Helm Provider.

**Distribution**: OCI Registry (`oci://registry.drycc.cc/charts`)

**Consumed by**: Crossplane `helm.m.crossplane.io/v1beta1 Release`

```yaml
forProvider:
  chart:
    name: valkey
    repository: oci://registry.drycc.cc/charts
    version: "0.1.0"
```

### Operator-based addons (e.g. valkey)

For addons that use a third-party Kubernetes operator (CRD-based):

```
addons/<name>/
  → renders one <Kind> CR (e.g. ValkeyCluster)
  → reconciled by the cluster-scoped operator
```

The operator and its CRDs are installed separately as a cluster-wide prerequisite. They
are **not** bundled per-instance. See "Prerequisites: install the operator" below.

For non-operator addons (e.g. redis), the addon chart is a full StatefulSet-based chart
(based on the bitnami pattern).

## classes/

Crossplane control plane configuration packaged as a Helm chart. Installs XRD
(CompositeResourceDefinition), Composition, and AddonClass resources that enable the
platform to provision addons on demand.

**Data-driven**: The `classes/files/*.yaml` files are the sole source of truth. The
templates (`definitions.yaml`, `compositions.yaml`, `addonclasses.yaml`) iterate over
them via `.Files.Glob` to generate the entire control plane. Adding a new addon requires
only adding a `files/<name>.yaml` — no template changes.

**Distribution**: Helm Repository

**Consumed by**: Platform operators via `helm install`

### Installation

```bash
helm install catalog ./classes
```

To update or reinstall:

```bash
helm upgrade --install catalog ./classes
```

### Deployment order

Helm hooks ensure correct ordering:

| Resource | Hook Weight | Description |
|----------|:---:|-------------|
| AddonClass CRD | `-10` | Platform-level CRD, installed first |
| Helm ProviderConfig | `-9` | Crossplane Helm provider configuration |
| XRD (per service) | `1` | CompositeResourceDefinition, must exist before Composition |
| Composition (per service) | `2` | Maps XR to Helm Release, must exist before AddonClass |
| AddonClass CR (per service) | `3` | Addon class entry with plans |

### Data flow

```
classes/files/<name>.yaml
       │ (.Files.Glob loop)
       ├─→ XRD (<plural>.addons.drycc.cc)
       ├─→ Composition (helm Release → pulls addons/<name>/)
       └─→ AddonClass (addons.drycc.cc, plans + whitelists)
                        │
                        │ spec.parameters → spec.forProvider.values
                        v
               addons/<name>/  →  renders one <Kind> CR
```

## Prerequisites: install third-party operators

For operator-based addons (e.g. valkey), the operator and its CRDs must be installed
as a cluster-wide prerequisite **before** any addon instance is created.

### Valkey Operator

```bash
helm install valkey-operator valkey-operator \
  --repo https://valkey.io/valkey-helm/ \
  --version 0.1.1 \
  --namespace valkey-system --create-namespace
```

- Chart: `valkey-operator` (repo `https://valkey.io/valkey-helm/`)
- Image: `ghcr.io/valkey-io/valkey-operator:v0.1.0`
- CRDs: `valkeyclusters.valkey.io`, `valkeynodes.valkey.io`

Verify:

```bash
kubectl get pods -n valkey-system
kubectl get crd | grep valkey.io
```

> Note: Helm does not upgrade or delete resources in `crds/` on `helm upgrade`/`helm uninstall`.
> Apply CRDs explicitly via `kubectl replace -f <raw-url>` when bumping operator versions.

## Adding a new addon

See `.AGENTS.md` for agent instructions on migrating a new operator-based addon.
Reference implementation: `addons/valkey/`.
