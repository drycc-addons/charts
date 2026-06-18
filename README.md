# Charts

Helm charts for the drycc addons platform. Two-layer data-driven model powered by Crossplane.

## Architecture: Crossplane + Helm backends

The platform is built on two cooperating backends: a **Crossplane control plane**
(`classes/`) that defines the addon catalog and provisioning logic, and a **Helm
rendering layer** (`addons/`) that produces the actual workload resources. Every
addon requires both halves — the control plane to declaratively describe *how* an
addon is provisioned, and the rendering layer to emit the concrete Kubernetes
resource.

### Crossplane control plane (`classes/`)

Installed once per cluster via `helm install catalog ./classes`. This chart renders
three Crossplane resource types per addon, all generated from data files in
`classes/files/`:

| Resource | Purpose |
|----------|---------|
| **XRD** (`CompositeResourceDefinition`) | Defines the composite kind (e.g. `Valkey`) and the `spec.parameters` schema. The XRD admission controller validates user input against this schema at creation time. |
| **Composition** | Pipeline-mode Composition that maps the composite resource (XR) to a Crossplane `helm.m.crossplane.io/v1beta1 Release`. It patches `spec.defaults → spec.parameters → spec.overrides` into `spec.forProvider.values`, which become the addon chart's helm values. |
| **AddonClass** (`addons.drycc.cc/v1`) | Platform-owned CR that advertises the addon kind, plans (`defaults`/`overrides`), and field whitelists (`allowCreate`/`allowUpdate`) to the PaaS API. |

A fourth resource, the Helm `ClusterProviderConfig` (`drycc-addons`), is installed
cluster-wide and uses `InjectedIdentity` so Crossplane can authenticate to the
cluster when creating `Release` objects.

**Value merge order** (lowest → highest priority):

```
spec.defaults   ← plan.defaults      (platform defaults, user-overridable)
spec.parameters ← filtered user input (validated by schema.yaml)
spec.overrides  ← plan.overrides     (platform-enforced, highest priority)
                         │
                         ▼  (Composition patches each into spec.forProvider.values)
              helm Release.values  →  addon chart  →  renders one CR
```

### Helm rendering layer (`addons/`)

Each `addons/<name>/` is a standalone Helm chart distributed via OCI registry and
pulled on demand by the Crossplane Helm provider. The chart renders **exactly one
custom resource** (e.g. a `ValkeyCluster` CR) — it contains no operator, no CRDs,
and no controllers. Top-level `values.yaml` keys map 1:1 to the target CR's
`.spec` fields.

```
Crossplane Composition
      │  creates helm.m.crossplane.io/v1beta1 Release
      ▼
helm Release  ──pull──►  oci://registry.drycc.cc/charts/<name>:<version>
      │                   (addon chart)
      ▼
helm template  ──renders──►  one <Kind> CR (e.g. ValkeyCluster)
      │
      ▼
cluster-scoped operator reconciles the CR  (installed separately)
```

For non-operator addons (e.g. `generic`), the chart renders a native
`StatefulSet` directly — no third-party operator involved.

### How the two backends connect

```
classes/files/<name>/              addons/<name>/
  meta.yaml    (kind, chart)         Chart.yaml
  schema.yaml  (admission)            values.yaml      ← merged values land here
  plans.yaml   (defaults/overrides)  templates/
         │                               │
         ▼                               ▼
  XRD + Composition + AddonClass     renders one CR
         │                               ▲
         ▼                               │
    user creates XR ──► Composition ──► helm Release (pulls chart, applies values)
```

The `classes/` chart and `addons/` chart are versioned independently. A bump to
the addon chart (`chartVersion` in `meta.yaml`) only requires updating the classes
declaration — no chart template changes needed.

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
├── AGENTS.md                 # Agent instructions for migrating new operators
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

See `AGENTS.md` for agent instructions on migrating a new operator-based addon.
Reference implementation: `addons/valkey/`.
