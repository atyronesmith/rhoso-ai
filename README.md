# Red Hat OpenStack Services on OpenShift (RHOSO) Deployment

This repository contains an automated deployment solution for RHOSO 18.0 on OpenShift Container Platform.

## Overview

The deployment solution includes:
- Ansible playbook for orchestrating the deployment
- Customizable network configuration through variables
- Kustomize integration for YAML customization
- Support for both pre-provisioned and bare-metal nodes
- Comprehensive error handling and validation

## Prerequisites

1. **OpenShift Container Platform 4.18** cluster with:
   - Cluster-admin privileges
   - MetalLB Operator capability
   - NMState Operator capability
   - Sufficient worker nodes for RHOSO services

2. **Workstation tools**:
   - `oc` CLI tool (logged into the cluster)
   - `ansible` and `ansible-playbook`
   - `kubectl` with kustomize
   - `jq` for JSON processing

3. **Subscriptions and credentials**:
   - Red Hat subscription for RHEL repositories
   - Red Hat registry credentials
   - Access to RHOSO 18.0 repositories

## Directory Structure

```
rhoso-deployment/
├── deploy-rhoso.sh              # Main deployment script
├── ansible/
│   ├── deploy-rhoso.yml         # Main Ansible playbook
│   ├── vars/
│   │   ├── network-config.yml   # Network configuration
│   │   └── deployment-config.yml # Deployment settings
│   ├── templates/               # Jinja2 templates for YAML generation
│   └── tasks/                   # Ansible task files
├── kustomize/                   # Generated Kustomize configurations
├── backups/                     # Backup directory
└── logs/                        # Deployment logs
```

## Quick Start

1. **Clone or create the deployment directory**:
   ```bash
   mkdir rhoso-deployment
   cd rhoso-deployment
   ```

2. **Create the deployment files** from the artifacts provided:
   - Save the deployment script as `deploy-rhoso.sh`
   - Create the Ansible structure and save the playbook
   - Save the variable files in `ansible/vars/`
   - Save the templates in `ansible/templates/`

3. **Make the deployment script executable**:
   ```bash
   chmod +x deploy-rhoso.sh
   ```

4. **Configure your environment**:

   Edit `ansible/vars/network-config.yml`:
   - Update network CIDRs for your environment
   - Modify interface names to match your hardware
   - Adjust IP ranges for your network design

   Edit `ansible/vars/deployment-config.yml`:
   - Set secure passwords (IMPORTANT for production!)
   - Configure service replica counts
   - Update node specifications
   - Add subscription manager credentials

5. **Run prerequisite checks**:
   ```bash
   ./deploy-rhoso.sh --check-only
   ```

6. **Perform a dry-run deployment**:
   ```bash
   ./deploy-rhoso.sh --dry-run
   ```

7. **Deploy RHOSO**:
   ```bash
   ./deploy-rhoso.sh --backup
   ```

## Configuration

### Network Configuration

The `network-config.yml` file allows you to customize all network settings:

```yaml
networks:
  ctlplane:
    cidr: 192.168.122.0/24      # Control plane network
    vlan_id: null                # No VLAN for ctlplane
    interface: enp6s0            # Physical interface
    metallb_pool:
      start: 192.168.122.80      # MetalLB VIP range
      end: 192.168.122.90
```

Key network customization options:
- **CIDR ranges**: Modify to match your data center
- **VLAN IDs**: Set appropriate VLAN tags
- **Interface names**: Update to match your hardware
- **MTU settings**: Configure jumbo frames for storage
- **IP allocations**: Adjust ranges to avoid conflicts

### Deployment Configuration

The `deployment-config.yml` file controls service deployment:

```yaml
control_plane:
  services:
    nova:
      api_replicas: 3           # Scale based on needs
    glance:
      api_replicas: 0           # Enable when storage configured
```

Important settings:
- **Service passwords**: Must be changed for production
- **Replica counts**: Scale based on requirements
- **Storage settings**: Configure backends before enabling
- **Feature flags**: Enable/disable optional services

## Advanced Usage

### Using Different Networks

To use custom network configurations:

1. Edit the networks section in `network-config.yml`
2. Add or remove networks as needed
3. Update node configurations to use the new networks
4. Regenerate with: `./deploy-rhoso.sh --dry-run`

### Kustomize Overlays

The deployment generates Kustomize configurations:

```bash
# View generated configuration
kubectl kustomize kustomize/overlays/production

# Apply custom patches
cd kustomize/overlays/production
cat > custom-patch.yaml << EOF
apiVersion: core.openstack.org/v1beta1
kind: OpenStackControlPlane
metadata:
  name: openstack-control-plane
spec:
  nova:
    template:
      apiServiceTemplate:
        replicas: 5
EOF

# Add to kustomization.yaml
echo "patchesStrategicMerge:" >> kustomization.yaml
echo "  - custom-patch.yaml" >> kustomization.yaml
```

### Multiple Environments

Deploy different environments:

```bash
# Development environment
./deploy-rhoso.sh -e development -d

# Staging environment
./deploy-rhoso.sh -e staging

# Production environment
./deploy-rhoso.sh -e production --backup
```

## Monitoring Deployment

Watch deployment progress:

```bash
# Overall status
watch 'oc get openstackcontrolplane,openstackdataplanenodeset,openstackdataplanedeployment -n openstack'

# Detailed pod status
oc get pods -n openstack -w

# Ansible job logs
oc logs -l app=openstackansibleee -f --max-log-requests 10
```

## Troubleshooting

### Common Issues

1. **Network Configuration Errors**:
   ```bash
   # Check network attachment definitions
   oc get nad -n openstack

   # Verify node network configs
   oc get nncp
   ```

2. **Service Deployment Failures**:
   ```bash
   # Check job status
   oc get jobs -n openstack

   # View job logs
   oc logs job/<job-name> -n openstack
   ```

3. **Storage Issues**:
   ```bash
   # Verify storage class
   oc get storageclass

   # Check PVC status
   oc get pvc -n openstack
   ```

### Debug Mode

Enable verbose output:
```bash
./deploy-rhoso.sh --verbose --dry-run
```

### Recovery

Restore from backup:
```bash
# List backups
ls -la backups/

# Restore specific backup
oc apply -f backups/20240613_120000/
```

## Security Considerations

1. **Change all default passwords** in `deployment-config.yml`
2. **Secure the SSH keys** used for node access
3. **Encrypt sensitive variable files** in production
4. **Use separate credentials** for each environment
5. **Enable TLS** for all services (default: enabled)

## Support

For issues and questions:
- Check the deployment logs in `logs/`
- Review the generated YAML in `kustomize/`
- Consult the official RHOSO documentation
- Access the OpenStack client: `oc rsh -n openstack openstackclient`

## License

This deployment solution follows the same licensing as the Red Hat OpenStack Services on OpenShift product documentation.
