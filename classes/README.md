# Crossplane Addon Class

Helm chart for deploying Crossplane XRD, Composition, and AddonClass resources from addon definitions in `files/*.yaml`.

## Structure

```
charts/catalog/
├── Chart.yaml
├── crds/                         # Crossplane CRD manifests
├── files/                        # addon definitions for each service
│   ├── airflow.yaml
│   ├── clickhouse.yaml
│   ├── cloudbeaver.yaml
│   └── ...
└── templates/
    ├── addonclasses.yaml         # AddonClass resources
    ├── compositions.yaml         # Crossplane Compositions
    ├── definitions.yaml          # CompositeResourceDefinitions
    └── provider-config.yaml      # Helm ProviderConfig
```

## Installation

```bash
helm install crossplane-addon ./charts/catalog
```

To update or reinstall:

```bash
helm upgrade --install crossplane-addon ./charts/catalog
```

## Service definitions

Each addon entry is defined in `charts/catalog/files/*.yaml`. These files specify service metadata, the target Helm chart, registry, version, provider config, and class plans.

Common fields include:

- `registry` - OCI registry for the service chart
- `chart` - Helm chart name
- `chartVersion` - chart version
- `providerConfigRef` - Crossplane Helm provider config name
- `displayName` - addon class display name
- `kind` / `plural` - composite kind naming
- `plans` - class plans with enforcedValues and createDefaults

## Deployment Order

Helm hooks ensure correct ordering:
1. AddonClass CRD / definitions (hook-weight: -10 / 1)
2. Helm ProviderConfig (hook-weight: -9)
3. XRD per service (hook-weight: 1)
4. Composition per service (hook-weight: 2)
5. AddonClass per service (hook-weight: 3)
