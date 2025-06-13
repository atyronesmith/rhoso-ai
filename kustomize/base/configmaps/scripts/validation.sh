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
