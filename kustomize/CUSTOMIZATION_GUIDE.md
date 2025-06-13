# Kustomize Customization Guide

## Directory Structure

```
kustomize/
├── base/                 # Base configurations
│   ├── networking/      # Network resources
│   ├── controlplane/    # Control plane resources
│   ├── dataplane/       # Data plane resources
│   ├── secrets/         # Secret resources
│   └── configmaps/      # ConfigMap resources
├── components/          # Reusable components
│   ├── monitoring/      # Monitoring additions
│   ├── storage/         # Storage customizations
│   └── security/        # Security enhancements
└── overlays/            # Environment-specific
    ├── development/     # Dev environment
    ├── staging/         # Staging environment
    └── production/      # Production environment
```

## Common Customizations

### 1. Change Storage Class

```yaml
# overlays/production/patches/storage-patch.yaml
apiVersion: core.openstack.org/v1beta1
kind: OpenStackControlPlane
metadata:
  name: openstack-control-plane
spec:
  storageClass: ceph-rbd
```

### 2. Scale Services

```yaml
# overlays/production/kustomization.yaml
replicas:
  - name: nova-api
    count: 5
  - name: neutron-api
    count: 5
```

### 3. Add Custom Configuration

```yaml
# overlays/production/patches/nova-config-patch.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nova-config-override
data:
  custom.conf: |
    [DEFAULT]
    debug = False
    [compute]
    cpu_allocation_ratio = 16.0
```

### 4. Enable Components

```yaml
# overlays/production/kustomization.yaml
components:
  - ../../components/monitoring
  - ../../components/security
```

### 5. Custom Network Configuration

```yaml
# overlays/production/patches/network-patch.yaml
apiVersion: network.openstack.org/v1beta1
kind: NetConfig
metadata:
  name: openstacknetconfig
spec:
  networks:
    - name: CustomNetwork
      cidr: 10.0.100.0/24
      vlan: 100
```

## Building and Applying

### Preview changes
```bash
kubectl kustomize overlays/production
```

### Apply to cluster
```bash
kubectl apply -k overlays/production
```

### Generate manifests
```bash
kubectl kustomize overlays/production > production-manifests.yaml
```

## Best Practices

1. **Never modify base/** - All customizations in overlays
2. **Use patches** for modifications
3. **Use components** for reusable features
4. **Version control** all customizations
5. **Test in lower environments** first

## Advanced Usage

### Strategic Merge Patches
```yaml
patchesStrategicMerge:
  - patch-file.yaml
```

### JSON Patches
```yaml
patchesJson6902:
  - target:
      version: v1
      kind: Deployment
      name: nova-api
    patch: |-
      - op: replace
        path: /spec/replicas
        value: 5
```

### Variable References
```yaml
vars:
  - name: SERVICE_NAME
    objref:
      kind: Service
      name: nova-api
    fieldref:
      fieldpath: metadata.name
```
