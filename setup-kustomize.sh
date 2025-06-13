#!/bin/bash
# setup-kustomize.sh - Create Kustomize directory structure and files for RHOSO deployment

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUSTOMIZE_DIR="${SCRIPT_DIR}/kustomize"
ANSIBLE_DIR="${SCRIPT_DIR}/ansible"
VARS_DIR="${ANSIBLE_DIR}/vars"

# Default environment
DEFAULT_ENV="${ENVIRONMENT:-production}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# Create directory structure
create_directory_structure() {
    log_info "Creating Kustomize directory structure..."

    # Base directories
    mkdir -p "${KUSTOMIZE_DIR}/base"/{networking,controlplane,dataplane,secrets,configmaps}

    # Components directory for reusable components
    mkdir -p "${KUSTOMIZE_DIR}/components"/{monitoring,storage,security}

    # Overlay directories for different environments
    local environments=("development" "staging" "production")
    for env in "${environments[@]}"; do
        mkdir -p "${KUSTOMIZE_DIR}/overlays/${env}"/{patches,resources,configmaps,secrets}
    done

    log_info "Directory structure created successfully"
}

# Create base networking resources
create_networking_base() {
    log_info "Creating base networking resources..."

    # Base kustomization for networking
    cat > "${KUSTOMIZE_DIR}/base/networking/kustomization.yaml" << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - nncp-worker-nodes.yaml
  - network-attachment-definitions.yaml
  - metallb-ipaddresspools.yaml
  - metallb-l2advertisements.yaml
  - netconfig.yaml

commonLabels:
  app.kubernetes.io/component: networking
  app.kubernetes.io/part-of: rhoso
EOF

    # NNCP for worker nodes
    cat > "${KUSTOMIZE_DIR}/base/networking/nncp-worker-nodes.yaml" << 'EOF'
# This file will be generated from templates
# Placeholder for NodeNetworkConfigurationPolicy resources
---
apiVersion: nmstate.io/v1
kind: NodeNetworkConfigurationPolicy
metadata:
  name: osp-enp6s0-worker-0
spec:
  nodeSelector:
    kubernetes.io/hostname: worker-0
    node-role.kubernetes.io/worker: ""
  desiredState:
    interfaces: []  # Will be populated by generator
EOF

    # Network Attachment Definitions
    cat > "${KUSTOMIZE_DIR}/base/networking/network-attachment-definitions.yaml" << 'EOF'
# This file will be generated from templates
# Placeholder for NetworkAttachmentDefinition resources
---
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: ctlplane
  namespace: openstack
spec:
  config: |
    {
      "cniVersion": "0.3.1",
      "name": "ctlplane",
      "type": "macvlan"
    }
EOF

    # MetalLB IP Address Pools
    cat > "${KUSTOMIZE_DIR}/base/networking/metallb-ipaddresspools.yaml" << 'EOF'
# This file will be generated from templates
# Placeholder for IPAddressPool resources
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: ctlplane
  namespace: metallb-system
spec:
  addresses: []  # Will be populated by generator
  autoAssign: true
  avoidBuggyIPs: false
EOF

    # MetalLB L2 Advertisements
    cat > "${KUSTOMIZE_DIR}/base/networking/metallb-l2advertisements.yaml" << 'EOF'
# This file will be generated from templates
# Placeholder for L2Advertisement resources
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: ctlplane
  namespace: metallb-system
spec:
  ipAddressPools:
    - ctlplane
  interfaces: []  # Will be populated by generator
EOF

    # NetConfig
    cat > "${KUSTOMIZE_DIR}/base/networking/netconfig.yaml" << 'EOF'
# This file will be generated from templates
# Placeholder for NetConfig resource
---
apiVersion: network.openstack.org/v1beta1
kind: NetConfig
metadata:
  name: openstacknetconfig
  namespace: openstack
spec:
  networks: []  # Will be populated by generator
EOF
}

# Create base control plane resources
create_controlplane_base() {
    log_info "Creating base control plane resources..."

    # Base kustomization for control plane
    cat > "${KUSTOMIZE_DIR}/base/controlplane/kustomization.yaml" << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - openstackcontrolplane.yaml
  - services-config.yaml

configMapGenerator:
  - name: service-config-overrides
    files:
      - configs/nova.conf
      - configs/neutron.conf
      - configs/cinder.conf

commonLabels:
  app.kubernetes.io/component: controlplane
  app.kubernetes.io/part-of: rhoso
EOF

    # Create configs directory
    mkdir -p "${KUSTOMIZE_DIR}/base/controlplane/configs"

    # OpenStackControlPlane resource
    cat > "${KUSTOMIZE_DIR}/base/controlplane/openstackcontrolplane.yaml" << 'EOF'
# This file will be generated from templates
# Placeholder for OpenStackControlPlane resource
---
apiVersion: core.openstack.org/v1beta1
kind: OpenStackControlPlane
metadata:
  name: openstack-control-plane
  namespace: openstack
spec:
  secret: osp-secret
  storageClass: local-storage  # Will be replaced by kustomize
EOF

    # Services configuration
    cat > "${KUSTOMIZE_DIR}/base/controlplane/services-config.yaml" << 'EOF'
# Service-specific configuration overrides
# This file contains ConfigMaps for service customization
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: nova-config-override
  namespace: openstack
data:
  custom.conf: |
    [DEFAULT]
    # Custom Nova configuration
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: neutron-config-override
  namespace: openstack
data:
  custom.conf: |
    [DEFAULT]
    # Custom Neutron configuration
EOF

    # Example service config files
    cat > "${KUSTOMIZE_DIR}/base/controlplane/configs/nova.conf" << 'EOF'
[DEFAULT]
# Nova custom configuration
debug = False
transport_url = rabbit://nova:password@rabbitmq.openstack.svc.cluster.local:5672/

[api]
# API settings

[conductor]
# Conductor settings

[scheduler]
# Scheduler settings
EOF

    cat > "${KUSTOMIZE_DIR}/base/controlplane/configs/neutron.conf" << 'EOF'
[DEFAULT]
# Neutron custom configuration
debug = False
core_plugin = ml2

[ml2]
type_drivers = flat,vlan,vxlan
tenant_network_types = vxlan
mechanism_drivers = ovn

[ovn]
# OVN settings
EOF

    cat > "${KUSTOMIZE_DIR}/base/controlplane/configs/cinder.conf" << 'EOF'
[DEFAULT]
# Cinder custom configuration
debug = False
enabled_backends = lvm,nfs

[lvm]
# LVM backend settings

[nfs]
# NFS backend settings
EOF
}

# Create base data plane resources
create_dataplane_base() {
    log_info "Creating base data plane resources..."

    # Base kustomization for data plane
    cat > "${KUSTOMIZE_DIR}/base/dataplane/kustomization.yaml" << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - openstackdataplanenodeset.yaml
  - openstackdataplanedeployment.yaml
  - baremetalhosts.yaml

commonLabels:
  app.kubernetes.io/component: dataplane
  app.kubernetes.io/part-of: rhoso
EOF

    # OpenStackDataPlaneNodeSet resource
    cat > "${KUSTOMIZE_DIR}/base/dataplane/openstackdataplanenodeset.yaml" << 'EOF'
# This file will be generated from templates
# Placeholder for OpenStackDataPlaneNodeSet resource
---
apiVersion: dataplane.openstack.org/v1beta1
kind: OpenStackDataPlaneNodeSet
metadata:
  name: openstack-data-plane
  namespace: openstack
spec:
  preProvisioned: true
  tlsEnabled: true
  env:
    - name: ANSIBLE_FORCE_COLOR
      value: "True"
EOF

    # OpenStackDataPlaneDeployment resource
    cat > "${KUSTOMIZE_DIR}/base/dataplane/openstackdataplanedeployment.yaml" << 'EOF'
# This file will be generated from templates
# Placeholder for OpenStackDataPlaneDeployment resource
---
apiVersion: dataplane.openstack.org/v1beta1
kind: OpenStackDataPlaneDeployment
metadata:
  name: data-plane-deployment
  namespace: openstack
spec:
  nodeSets:
    - openstack-data-plane
EOF

    # BareMetalHost resources (for unprovisioned nodes)
    cat > "${KUSTOMIZE_DIR}/base/dataplane/baremetalhosts.yaml" << 'EOF'
# Placeholder for BareMetalHost resources
# Only used when preProvisioned: false
---
# apiVersion: metal3.io/v1alpha1
# kind: BareMetalHost
# metadata:
#   name: compute-0
#   namespace: openstack
# spec:
#   online: true
EOF
}

# Create base secrets and configmaps
create_base_secrets_configmaps() {
    log_info "Creating base secrets and configmaps..."

    # Base kustomization for secrets
    cat > "${KUSTOMIZE_DIR}/base/secrets/kustomization.yaml" << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - osp-secret.yaml
  - dataplane-secrets.yaml

secretGenerator:
  - name: additional-passwords
    literals:
      - additional-service-password=changeme
    options:
      disableNameSuffixHash: true

commonLabels:
  app.kubernetes.io/component: secrets
  app.kubernetes.io/part-of: rhoso
EOF

    # OSP Secret
    cat > "${KUSTOMIZE_DIR}/base/secrets/osp-secret.yaml" << 'EOF'
# This should be generated with secure passwords
# DO NOT use these default values in production!
---
apiVersion: v1
kind: Secret
metadata:
  name: osp-secret
  namespace: openstack
type: Opaque
data:
  AdminPassword: Y2hhbmdlbWUxMjMhCg==  # changeme123!
  # Add all other required passwords
EOF

    # Data plane secrets
    cat > "${KUSTOMIZE_DIR}/base/secrets/dataplane-secrets.yaml" << 'EOF'
---
apiVersion: v1
kind: Secret
metadata:
  name: dataplane-ansible-ssh-private-key-secret
  namespace: openstack
type: Opaque
data:
  ssh-privatekey: ""  # Will be populated
  ssh-publickey: ""   # Will be populated
---
apiVersion: v1
kind: Secret
metadata:
  name: nova-migration-ssh-key
  namespace: openstack
type: Opaque
data:
  ssh-privatekey: ""  # Will be populated
  ssh-publickey: ""   # Will be populated
EOF

    # Base kustomization for configmaps
    cat > "${KUSTOMIZE_DIR}/base/configmaps/kustomization.yaml" << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

configMapGenerator:
  - name: deployment-scripts
    files:
      - scripts/post-deployment.sh
      - scripts/validation.sh

commonLabels:
  app.kubernetes.io/component: configmaps
  app.kubernetes.io/part-of: rhoso
EOF

    # Create scripts directory
    mkdir -p "${KUSTOMIZE_DIR}/base/configmaps/scripts"

    # Post-deployment script
    cat > "${KUSTOMIZE_DIR}/base/configmaps/scripts/post-deployment.sh" << 'EOF'
#!/bin/bash
# Post-deployment validation and configuration script

echo "Running post-deployment tasks..."

# Discover compute hosts
oc rsh nova-cell0-conductor-0 nova-manage cell_v2 discover_hosts --verbose

# Verify services
oc rsh -n openstack openstackclient openstack service list

echo "Post-deployment tasks completed"
EOF

    # Validation script
    cat > "${KUSTOMIZE_DIR}/base/configmaps/scripts/validation.sh" << 'EOF'
#!/bin/bash
# Deployment validation script

echo "Validating RHOSO deployment..."

# Check control plane
oc get openstackcontrolplane -n openstack

# Check data plane
oc get openstackdataplanenodeset -n openstack

# Check services
oc get pods -n openstack

echo "Validation completed"
EOF

    chmod +x "${KUSTOMIZE_DIR}/base/configmaps/scripts/"*.sh
}

# Create main base kustomization
create_base_kustomization() {
    log_info "Creating main base kustomization..."

    cat > "${KUSTOMIZE_DIR}/base/kustomization.yaml" << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: openstack

resources:
  # Networking resources
  - networking/

  # Control plane resources
  - controlplane/

  # Data plane resources
  - dataplane/

  # Secrets
  - secrets/

  # ConfigMaps
  - configmaps/

# Common labels for all resources
commonLabels:
  app.kubernetes.io/name: rhoso
  app.kubernetes.io/instance: rhoso-deployment
  app.kubernetes.io/managed-by: kustomize

# Common annotations
commonAnnotations:
  rhoso.openstack.org/version: "18.0"
EOF
}

# Create environment overlays
create_environment_overlay() {
    local env=$1
    log_info "Creating overlay for environment: ${env}"

    local overlay_dir="${KUSTOMIZE_DIR}/overlays/${env}"

    # Main kustomization for the overlay
    cat > "${overlay_dir}/kustomization.yaml" << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: openstack

bases:
  - ../../base

namePrefix: ${env}-
nameSuffix: ""

commonLabels:
  environment: ${env}

commonAnnotations:
  deployment.rhoso.openstack.org/environment: ${env}

# Environment-specific patches
patchesStrategicMerge:
  - patches/controlplane-patch.yaml
  - patches/dataplane-patch.yaml

# Environment-specific resources
resources:
  - resources/extra-secrets.yaml

# ConfigMap customization
configMapGenerator:
  - name: ${env}-config
    literals:
      - environment=${env}
      - debug=true

# Secret customization
secretGenerator:
  - name: ${env}-credentials
    literals:
      - username=admin
      - password=changeme
    options:
      disableNameSuffixHash: true

# Variable substitution
vars:
  - name: STORAGE_CLASS
    objref:
      kind: StorageClass
      name: ${env}-storage
      apiVersion: storage.k8s.io/v1
  - name: ENVIRONMENT
    objref:
      kind: ConfigMap
      name: ${env}-config
      apiVersion: v1
    fieldref:
      fieldpath: data.environment

# Image customization (if needed)
images:
  - name: registry.redhat.io/rhosp-dev-preview/openstack-nova-compute-rhel9
    newTag: 18.0-${env}

# Replica customization
replicas:
  - name: keystone
    count: $([ "${env}" == "production" ] && echo 5 || echo 1)
EOF

    # Control plane patch
    cat > "${overlay_dir}/patches/controlplane-patch.yaml" << EOF
apiVersion: core.openstack.org/v1beta1
kind: OpenStackControlPlane
metadata:
  name: openstack-control-plane
spec:
  storageClass: ${env}-storage-class
  # Environment-specific overrides
  keystone:
    template:
      replicas: $([ "${env}" == "production" ] && echo 5 || echo 1)
  nova:
    template:
      apiServiceTemplate:
        replicas: $([ "${env}" == "production" ] && echo 3 || echo 1)
      metadataServiceTemplate:
        replicas: $([ "${env}" == "production" ] && echo 3 || echo 1)
  neutron:
    template:
      replicas: $([ "${env}" == "production" ] && echo 3 || echo 1)
  cinder:
    template:
      cinderAPI:
        replicas: $([ "${env}" == "production" ] && echo 3 || echo 1)
EOF

    # Data plane patch
    cat > "${overlay_dir}/patches/dataplane-patch.yaml" << EOF
apiVersion: dataplane.openstack.org/v1beta1
kind: OpenStackDataPlaneNodeSet
metadata:
  name: openstack-data-plane
spec:
  nodeTemplate:
    ansible:
      ansibleVars:
        # Environment-specific Ansible variables
        edpm_debug: $([ "${env}" == "development" ] && echo "true" || echo "false")
        edpm_environment: ${env}
EOF

    # Extra resources
    cat > "${overlay_dir}/resources/extra-secrets.yaml" << EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: ${env}-extra-secret
  namespace: openstack
type: Opaque
stringData:
  environment: ${env}
  extra-config: |
    # Environment-specific configuration
    debug: $([ "${env}" == "development" ] && echo "true" || echo "false")
EOF
}

# Create components
create_components() {
    log_info "Creating reusable components..."

    # Monitoring component
    cat > "${KUSTOMIZE_DIR}/components/monitoring/kustomization.yaml" << 'EOF'
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component

resources:
  - prometheus-rules.yaml
  - grafana-dashboards.yaml

configMapGenerator:
  - name: monitoring-config
    files:
      - dashboards/nova-dashboard.json
      - dashboards/neutron-dashboard.json
EOF

    mkdir -p "${KUSTOMIZE_DIR}/components/monitoring/dashboards"

    # Storage component
    cat > "${KUSTOMIZE_DIR}/components/storage/kustomization.yaml" << 'EOF'
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component

patchesStrategicMerge:
  - cinder-backend-patch.yaml
  - glance-backend-patch.yaml

configMapGenerator:
  - name: storage-config
    literals:
      - backend=ceph
      - pool=openstack
EOF

    # Security component
    cat > "${KUSTOMIZE_DIR}/components/security/kustomization.yaml" << 'EOF'
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component

resources:
  - network-policies.yaml
  - pod-security-policies.yaml

patchesStrategicMerge:
  - tls-patch.yaml
EOF
}

# Create example customization guide
create_customization_guide() {
    log_info "Creating customization guide..."

    cat > "${KUSTOMIZE_DIR}/CUSTOMIZATION_GUIDE.md" << 'EOF'
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
EOF
}

# Generate script
generate_from_config() {
    log_info "Generating Kustomize files from configuration..."

    # Check if config files exist
    if [[ ! -f "${VARS_DIR}/network-config.yml" ]] || [[ ! -f "${VARS_DIR}/deployment-config.yml" ]]; then
        log_warn "Configuration files not found. Skipping generation."
        log_warn "Run the Ansible playbook to generate files from templates."
        return
    fi

    cat > "${KUSTOMIZE_DIR}/generate.sh" << 'EOF'
#!/bin/bash
# Generate Kustomize files from Ansible templates

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="${SCRIPT_DIR}/../ansible"

echo "Generating Kustomize files from templates..."

# Run Ansible playbook in check mode to generate files
ansible-playbook \
    -i localhost, \
    "${ANSIBLE_DIR}/deploy-rhoso.yml" \
    -e "@${ANSIBLE_DIR}/vars/network-config.yml" \
    -e "@${ANSIBLE_DIR}/vars/deployment-config.yml" \
    -e "dry_run=true" \
    -e "kustomize_only=true" \
    --tags generate-kustomize

echo "Generation complete!"
EOF

    chmod +x "${KUSTOMIZE_DIR}/generate.sh"
}

# Main execution
main() {
    log_info "Setting up Kustomize structure for RHOSO deployment"

    # Create directory structure
    create_directory_structure

    # Create base resources
    create_networking_base
    create_controlplane_base
    create_dataplane_base
    create_base_secrets_configmaps
    create_base_kustomization

    # Create overlays for each environment
    local environments=("development" "staging" "production")
    for env in "${environments[@]}"; do
        create_environment_overlay "$env"
    done

    # Create reusable components
    create_components

    # Create customization guide
    create_customization_guide

    # Create generation script
    generate_from_config

    log_info "Kustomize setup complete!"
    log_info "Directory structure created at: ${KUSTOMIZE_DIR}"
    log_info ""
    log_info "Next steps:"
    log_info "1. Review and customize files in ${KUSTOMIZE_DIR}"
    log_info "2. Run '${KUSTOMIZE_DIR}/generate.sh' to generate from templates"
    log_info "3. Preview with: kubectl kustomize ${KUSTOMIZE_DIR}/overlays/production"
    log_info "4. Apply with: kubectl apply -k ${KUSTOMIZE_DIR}/overlays/production"
    log_info ""
    log_info "See ${KUSTOMIZE_DIR}/CUSTOMIZATION_GUIDE.md for customization examples"
}

# Show usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -d, --dir DIR  Specify Kustomize directory (default: ./kustomize)"
    echo "  -e, --env ENV  Specify default environment (default: production)"
    echo ""
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -d|--dir)
            KUSTOMIZE_DIR="$2"
            shift 2
            ;;
        -e|--env)
            DEFAULT_ENV="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Run main function
main