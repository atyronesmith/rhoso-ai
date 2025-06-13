# RHOSO Deployment Quick Start Guide

## 🚀 Quick Deployment (5 minutes)

### 1. Prerequisites Check
```bash
# Check tools
which oc ansible-playbook kubectl jq || echo "Missing tools!"

# Login to OpenShift
oc login --server=https://api.ocp.example.com:6443 -u admin

# Verify cluster access
oc auth can-i '*' '*' --all-namespaces
```

### 2. Setup
```bash
# Clone and setup
git clone <repository>
cd rhoso-deployment
make setup
```

### 3. Configure Networks
Edit `ansible/vars/network-config.yml`:
- Update CIDRs to match your network
- Set correct VLAN IDs
- Update interface names (e.g., enp6s0)

### 4. Configure Deployment
Edit `ansible/vars/deployment-config.yml`:
- **CRITICAL**: Generate new passwords
  ```bash
  make generate-passwords
  ```
- Update subscription manager credentials
- Adjust service replica counts if needed

### 5. Validate Configuration
```bash
# Test network configuration
make test-network

# Run pre-flight checks
make check
```

### 6. Deploy
```bash
# Dry run first (recommended)
make dry-run

# Deploy to production
make deploy

# Or use the script directly
./deploy-rhoso.sh
```

### 7. Monitor Deployment
```bash
# Watch deployment status
make watch

# Check logs
make logs
```

## 📊 Post-Deployment

### Access OpenStack
```bash
# OpenStack CLI
make shell

# List services
make endpoints
```

### Verify Services
```bash
oc rsh -n openstack openstackclient
openstack service list
openstack endpoint list
openstack network agent list
```

## 🔧 Common Customizations

### Different Network Setup
1. Edit `ansible/vars/network-config.yml`
2. Update network names, CIDRs, VLANs
3. Run `make test-network` to validate

### Add Custom Service Configuration
1. Create patch in `kustomize/overlays/production/`
2. Update `kustomization.yaml` to include patch
3. Rebuild with `make deploy`

### Scale Services
Edit `ansible/vars/deployment-config.yml`:
```yaml
control_plane:
  services:
    nova:
      api_replicas: 5  # Increase API replicas
    neutron:
      api_replicas: 5
```

## 🚨 Troubleshooting

### Deployment Fails
```bash
# Check latest log
make logs

# Check service jobs
oc get jobs -n openstack
oc logs job/<failing-job> -n openstack
```

### Network Issues
```bash
# Verify network policies
oc get nncp
oc get nad -n openstack

# Check MetalLB
oc get ipaddresspool -n metallb-system
```

### Service Not Ready
```bash
# Check control plane status
oc describe openstackcontrolplane -n openstack

# Check specific service
oc get pods -n openstack | grep <service>
oc logs <service-pod> -n openstack
```

## 📝 Quick Commands Reference

| Task | Command |
|------|---------|
| Deploy | `make deploy` |
| Dry run | `make dry-run` |
| Check status | `make status` |
| Watch deployment | `make watch` |
| View logs | `make logs` |
| OpenStack CLI | `make shell` |
| List endpoints | `make endpoints` |
| Backup | `make backup` |
| Clean up | `make clean` |

## 🔐 Security Checklist

- [ ] Changed all default passwords
- [ ] Updated subscription manager credentials
- [ ] Updated registry credentials
- [ ] Reviewed network isolation
- [ ] Enabled TLS (if required)
- [ ] Configured firewall rules

## 📚 Additional Resources

- [Full README](README.md)
- [Network Configuration Guide](docs/networks.md)
- [Troubleshooting Guide](docs/troubleshooting.md)
- [Official RHOSO Documentation](https://docs.redhat.com)

## 💡 Tips

1. **Always dry-run first**: `make dry-run`
2. **Monitor logs during deployment**: `make logs` in another terminal
3. **Backup before changes**: `make backup`
4. **Use environments**: Deploy to dev first with `ENV=development`
5. **Validate networks**: Run `make test-network` before deployment

---
**Need help?** Check deployment logs, review status with `make status`, or consult the troubleshooting guide.
