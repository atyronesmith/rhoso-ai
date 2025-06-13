# RHOSO Kustomize Setup and Management

This directory contains scripts and tools for managing Red Hat OpenStack Services on OpenShift (RHOSO) deployments using Kustomize.

## 🚀 Quick Start

```bash
# 1. Make scripts executable
chmod +x *.sh

# 2. Run the workflow manager
./kustomize-workflow.sh

# 3. Follow the interactive menu
```

## 📁 Scripts Overview

### 1. **setup-kustomize.sh**
Creates the complete Kustomize directory structure with base configurations and environment overlays.

```bash
./setup-kustomize.sh [OPTIONS]
  -d, --dir DIR   Specify Kustomize directory (default: ./kustomize)
  -e, --env ENV   Specify default environment (default: production)
```

**What it creates:**
```
kustomize/
├── base/
│   ├── networking/         # Network configurations
│   ├── controlplane/       # Control plane resources
│   ├── dataplane/         # Data plane resources
│   ├── secrets/           # Secret resources
│   └── configmaps/        # ConfigMap resources
├── components/            # Reusable components
│   ├── monitoring/        # Monitoring additions
│   ├── storage/          # Storage customizations
│   └── security/         # Security enhancements
└── overlays/             # Environment-specific configs
    ├── development/      # Dev environment
    ├── staging/          # Staging environment
    └── production/       # Production environment
```

### 2. **validate-kustomize.sh**
Validates Kustomize configurations and checks for common issues.

```bash
./validate-kustomize.sh [OPTIONS] [ENVIRONMENT]
  -a, --all      Validate all environments
  -d, --diff     Show diff between environments
  -r, --report   Generate detailed report only
  -v, --verbose  Enable verbose output
```

**Validation checks:**
- ✓ Kustomize build success
- ✓ Required resources present
- ✓ Network configuration validity
- ✓ CIDR conflict detection
- ✓ Resource limits and requests
- ✓ Dry-run apply test

### 3. **convert-to-kustomize.sh**
Converts existing YAML resources into Kustomize structure.

```bash
./convert-to-kustomize.sh [SOURCE] [OPTIONS]
  -o, --output   Output directory (default: ./kustomize)
  -f, --force    Overwrite existing directory
```

**Features:**
- Automatically categorizes resources
- Splits multi-document YAML files
- Creates environment-specific patches
- Generates base kustomization files

### 4. **kustomize-workflow.sh**
Master script with interactive menu for complete workflow management.

```bash
# Interactive mode
./kustomize-workflow.sh

# Automation mode
./kustomize-workflow.sh [ACTION] [ENVIRONMENT]
```

**Actions:**
- `validate` - Validate configuration
- `build` - Build manifests
- `deploy` - Deploy to cluster
- `deploy-dry-run` - Test deployment

## 📋 Complete Workflow

### Step 1: Initial Setup

```bash
# Create Kustomize structure
./setup-kustomize.sh

# Or convert existing YAML files
./convert-to-kustomize.sh /path/to/yaml/files
```

### Step 2: Configure Networks

Edit `ansible/vars/network-config.yml` with your network settings:

```yaml
networks:
  ctlplane:
    cidr: 192.168.122.0/24
    vlan_id: null
    interface: enp6s0
  # ... other networks
```

### Step 3: Generate from Templates

If using Ansible templates:

```bash
# Run workflow manager and select option 2
./kustomize-workflow.sh
# Select: 2) Generate from Ansible templates
```

### Step 4: Customize for Environment

Edit overlay files for each environment:

```bash
# Development customization
vi kustomize/overlays/development/kustomization.yaml

# Production patches
vi kustomize/overlays/production/patches/controlplane-patch.yaml
```

### Step 5: Validate Configuration

```bash
# Validate all environments
./validate-kustomize.sh --all

# Or validate specific environment
./validate-kustomize.sh production
```

### Step 6: Build and Review

```bash
# Build manifests
kubectl kustomize kustomize/overlays/production > production.yaml

# Review the output
less production.yaml
```

### Step 7: Deploy

```bash
# Dry-run first
kubectl apply -k kustomize/overlays/production --dry-run=client

# Deploy
kubectl apply -k kustomize/overlays/production
```

## 🎨 Customization Examples

### Scale Services for Production

`kustomize/overlays/production/patches/scale-patch.yaml`:
```yaml
apiVersion: core.openstack.org/v1beta1
kind: OpenStackControlPlane
metadata:
  name: openstack-control-plane
spec:
  nova:
    template:
      apiServiceTemplate:
        replicas: 5
  neutron:
    template:
      replicas: 5
```

### Add Custom Network

`kustomize/overlays/production/patches/network-patch.yaml`:
```yaml
apiVersion: network.openstack.org/v1beta1
kind: NetConfig
metadata:
  name: openstacknetconfig
spec:
  networks:
    - name: CustomNet
      cidr: 10.0.100.0/24
      vlan: 100
```

### Environment-Specific Storage

`kustomize/overlays/production/kustomization.yaml`:
```yaml
patchesStrategicMerge:
  - patches/storage-class-patch.yaml

patches:
  - target:
      kind: OpenStackControlPlane
      name: openstack-control-plane
    patch: |-
      - op: replace
        path: /spec/storageClass
        value: ceph-rbd
```

## 🔧 Advanced Usage

### Using Components

Enable reusable components in your overlay:

```yaml
# kustomize/overlays/production/kustomization.yaml
components:
  - ../../components/monitoring
  - ../../components/security
```

### Variable Substitution

```yaml
# Define variables
vars:
  - name: STORAGE_CLASS
    objref:
      kind: StorageClass
      name: production-storage
      apiVersion: storage.k8s.io/v1

# Use in patches
spec:
  storageClass: $(STORAGE_CLASS)
```

### Multiple Environments

Create custom environments:

```bash
# Use workflow manager
./kustomize-workflow.sh
# Select: 8) Create custom overlay

# Or manually
mkdir -p kustomize/overlays/qa
cp -r kustomize/overlays/staging/* kustomize/overlays/qa/
# Edit as needed
```

## 🐛 Troubleshooting

### Validation Failures

```bash
# Get detailed error output
./validate-kustomize.sh production -v

# Check specific build errors
kubectl kustomize kustomize/overlays/production 2>&1
```

### Build Errors

Common issues:
- Missing resources in base
- Invalid YAML syntax
- Patch target not found
- Duplicate resource definitions

### Debugging Tips

```bash
# Show what files are included
kubectl kustomize kustomize/overlays/production --enable-alpha-plugins --output /dev/null

# Test individual patches
kubectl patch -f base.yaml --patch-file patch.yaml --dry-run=client -o yaml
```

## 📚 Best Practices

1. **Never modify base/** - All customizations go in overlays
2. **Use strategic merge patches** for modifications
3. **Keep secrets separate** - Use secretGenerator or external secrets
4. **Version control everything** - Track all changes
5. **Test in lower environments** before production
6. **Use components** for reusable features
7. **Document customizations** in overlay README files

## 🔗 Integration with CI/CD

```bash
# GitLab CI example
validate:
  script:
    - ./kustomize-workflow.sh validate $CI_ENVIRONMENT_NAME

build:
  script:
    - ./kustomize-workflow.sh build $CI_ENVIRONMENT_NAME > manifests.yaml
  artifacts:
    paths:
      - manifests.yaml

deploy:
  script:
    - ./kustomize-workflow.sh deploy $CI_ENVIRONMENT_NAME
  only:
    - main
```

## 📖 Additional Resources

- [Kustomize Documentation](https://kustomize.io/)
- [OpenShift GitOps](https://docs.openshift.com/container-platform/latest/cicd/gitops/understanding-openshift-gitops.html)
- [RHOSO Documentation](https://docs.redhat.com/)

## 🤝 Contributing

1. Test changes in development environment
2. Validate all environments
3. Document customizations
4. Submit merge request with validation report

---

For interactive help, run: `./kustomize-workflow.sh`