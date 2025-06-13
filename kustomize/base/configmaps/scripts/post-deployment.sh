#!/bin/bash
# Post-deployment validation and configuration script

echo "Running post-deployment tasks..."

# Discover compute hosts
oc rsh nova-cell0-conductor-0 nova-manage cell_v2 discover_hosts --verbose

# Verify services
oc rsh -n openstack openstackclient openstack service list

echo "Post-deployment tasks completed"
