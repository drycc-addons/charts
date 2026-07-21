# drycc addons charts — Agent Instructions

## Adding a new operator-based addon

When asked to migrate a third-party Kubernetes operator (RabbitMQ, MySQL, etc.):

1. **Reference implementation**: `addons/valkey/` is the canonical example. Copy its structure, adapt the values to the target CRD's `.spec` fields.
2. **Operator placement**: Install the operator + CRDs as a cluster-scoped prerequisite (outside this `charts/` directory). The addon chart only renders a single CR instance.
3. **Field filtering**: Delete fields users cannot reach in PaaS mode (`drycc addons create <name> <kind> <plan>`):
   - `existingSecret` / `*fromSecret` — no way to pre-stage
   - `image` (override) — operator chooses the image
   - `containers` (strategic merge) — escape hatch
   - `affinity` / `tolerations` — platform scheduling via presets
   - `nameOverride` / `commonLabels` / `commonAnnotations` — Composition already patches
   - Keep: `imagePullPolicy` (platform passthrough, not a CRD field)
4. **TLS handling**: Check the operator's source code for `tls-port` + `port 0` (TLS-only) vs mixed mode. If TLS-only, keep `tls.enabled` toggleable — never force-enable.
5. **Self-signed cert**: If the operator requires a pre-existing secret, generate one in the chart using `genCA` + `genSignedCert`. Use `lookup` to preserve certs on upgrade. Inspect operator source for Service naming to set correct SANs.
6. **Classes declaration**: Create `classes/files/<name>/` directory with three files (see directory structure below). The templates in `classes/templates/` automatically generate XRD, Composition, and AddonClass.
7. **Helm v4**: Do NOT include `engine: gotpl` in Chart.yaml (strict parser rejects it).
8. **XRD schema validation**: Add `classes/files/<name>/schema.yaml` with OpenAPI v3 schema for `spec.parameters`. Only include fields from `allowCreate` / `allowUpdate`. The XRD admission controller validates user input against this schema.

## Architecture overview

```
classes/files/<name>/          →  addon declaration (directory layout)
  meta.yaml                    →  kind, registry, chart info
  schema.yaml                  →  OpenAPI v3 schema for XRD admission validation
  plans.yaml                   →  plan definitions
classes/files/<name>.yaml      →  legacy single-file layout (still supported)
addons/<name>/                  →  renders one <Kind> CR (per-instance Helm chart)
<Operator> + CRDs               →  installed separately, cluster-wide
```

Crossplane Composition merges `spec.defaults → spec.parameters → spec.overrides` on the helm Release,
which flows into the addon chart as helm values.

## Directory structure

### Addon Helm chart

```
addons/<name>/
  Chart.yaml          # No engine: gotpl (Helm v4)
  values.yaml         # Top-level keys = CRD .spec fields. Use ## @param docs.
  .helmignore
  templates/
    _helpers.tpl        # defines: <name>.name, <name>.labels, <name>.tlsSecretName
    <kind>.yaml         # Renders the single CR (apiVersion, kind, metadata, spec)
    tls-secret.yaml     # Self-signed cert (only if operator needs pre-existing TLS secret)
    NOTES.txt
```

### Classes declaration (two layouts, both supported)

**Directory layout (preferred):**

```
classes/files/<name>/
  meta.yaml             # kind, plural, description, registry, chart, chartVersion, providerConfigRef, storageModel, multiplierFrom, visiblePaths
  schema.yaml           # OpenAPI v3 schema for XRD admission validation (only allowPathFields)
  plans.yaml            # list of plan definitions
```

**Legacy single-file layout (still works):**

```
classes/files/<name>.yaml
  kind: <Kind>
  plural: <plural>
  description: "<human-readable>"
  registry: oci://registry.drycc.cc/charts
  chart: <name>
  chartVersion: "<version>"
  providerConfigRef: drycc-addons
  parameters:           # OpenAPI v3 schema (optional)
  plans:
    - name: "<plan-name>"
      description: "..."
      defaults:           # plan defaults, user can override via spec.parameters
      overrides:          # platform-enforced, cannot be overridden by users
      allowCreate:
      allowUpdate:
```

### Plan field semantics

Plan fields MUST follow this order:

```yaml
- name: "small"
  description: "..."     # Human-readable plan description
  defaults: {}          # Platform defaults (lowest priority)
  overrides: {}         # Platform-enforced (highest priority)
  allowCreate: [...]    # Fields users may set at creation
  allowUpdate: [...]    # Fields users may modify after creation
```

| Field | Maps to XR | Behavior |
|---|---|---|
| `defaults` | `spec.defaults` | Plan defaults, user can override via `spec.parameters`. |
| `overrides` | `spec.overrides` | Platform-enforced, merged last. Users CANNOT override. |
| `allowCreate` | schema validation | Fields users may set when creating the addon. |
| `allowUpdate` | schema validation | Fields users may modify after creation. |
| `schema.yaml` | `spec.parameters` validation | OpenAPI v3 schema — matches `allowCreate` union. |

### Schema security constraints

All user-facing fields in `schema.yaml` MUST include size limits to protect
K8s etcd from abuse. Every field type needs constraints:

| Field type | Constraint | Default limit |
|---|---|---|
| Map/object keys | `maxProperties` | 50 |
| String values | `maxLength` | 4096 (8192 for env) |
| String arrays | `maxItems` + item `maxLength` | 50 items, 512 chars each |
| General arrays | `maxItems` | 20 |
| Integer | `minimum` / `maximum` | per addon logic |

**Rule**: If a user can write to it via `allowCreate`, it MUST have
size limits in `schema.yaml`. No exceptions.

```
user → drycc addons create <kind> <name> --plan <plan> --set <field>=<value>
  ↓
platform reads AddonClass
  ↓
XR creation:
  spec.defaults    ← plan.defaults          (platform defaults, user-overridable)
  spec.parameters      ← filtered user inputs      (validated by schema.yaml)
  spec.overrides   ← plan.overrides            (platform-enforced, highest priority)
  ↓
Composition merges: defaults → parameters → overrides → helm Release values
```

Django does **not** merge values. It writes the three fields directly to the XR.
Crossplane `function-patch-and-transform` merges them sequentially into `spec.forProvider.values`.

### Persistence design (generic addon)

Generic is billed by plan + usage. Persistence is user-configurable at create time:

- `persistence.enabled` — create-only
- `persistence.size` — create-only (PVC size immutable)
- `persistence.storageClassName` — create-only (PVC storageClass immutable)
- `persistence.mountPath` — create-only

Plan `defaults` provides baseline values. User can override at creation.
For operator-based addons (e.g., valkey), topology (shards/replicas) remains enforced.

### storageModel field

Set in `meta.yaml`, rendered into the AddonClass CR spec. The platform (billing) reads this from the AddonClass, NOT from `meta.yaml` directly.

```yaml
storageModel: custom     # or: bundle
```

| Value | Meaning | Billing storage source |
|---|---|---|
| `custom` | User can customize storage size at creation | Query K8s PVC actual size |
| `bundle` | Plan-enforced or no persistence | No PVC query needed |

### multiplierFrom field

Set in `meta.yaml`, rendered into the AddonClass CR spec. The platform (billing)
reads this from the AddonClass to calculate the billing multiplier. This is a
fixed platform property - users cannot set or change it.

```yaml
multiplierFrom: "replicas"   # dot-notation path into plan defaults / user parameters
```

When `multiplierFrom` is present, the controller resolves the field value from
plan `overrides` first (highest priority), then user `parameters`, then plan
`defaults`, then `1`. When absent, the multiplier defaults to `1`
(no multiplier calculation).

| Addon | `multiplierFrom` | Billing multiplier |
|---|---|---|
| `generic` | `replicas` | User-defined replica count (1-7) |
| `valkey` | *(absent)* | `1` (plan-enforced topology, billed by plan) |

### visiblePaths field

Set in `meta.yaml`, rendered into the AddonClass CR spec. The platform reads
this from the AddonClass to decide which plan-level fields are visible to end
users when listing/inspecting addon plans. Internal fields (`defaults`,
`overrides`) are hidden by omission.

```yaml
visiblePaths:
  - "name"           # plan name (e.g. "small")
  - "description"    # human-readable plan description
  - "allowCreate"    # fields users may set at creation
  - "allowUpdate"    # fields users may modify after creation
```

| Value | Plan field | Visible to users? |
|---|---|---|
| `name` | plan name | Yes |
| `description` | plan description | Yes |
| `allowCreate` | creatable field paths | Yes |
| `allowUpdate` | updatable field paths | Yes |
| `defaults` | platform defaults | No (internal) |
| `overrides` | platform-enforced values | No (internal) |

When absent, the platform falls back to its default visible set.

## Existing addons

| Addon | Type | CRD | Topology control | Persistence |
|---|---|---|---|---|
| `generic` | Native StatefulSet | N/A | Plan resources, user replicas (1-7), user persistence | `custom` (bill by PVC) |
| `valkey` | Operator (ValkeyCluster) | `valkey.io/v1alpha1` | Plan-enforced shards + replicas | `bundle` (bill by plan) |
