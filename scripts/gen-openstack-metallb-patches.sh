#!/bin/bash
#
# Copyright 2024 Red Hat Inc.
#
# Generate kustomize patches for OpenStack service MetalLB pool annotations
# This script creates JSON patches to update metallb.universe.tf/address-pool annotations
# for multi-RHOSO deployments
#

set -e

if [ -z "${NAMESPACE}" ]; then
    echo "ERROR: NAMESPACE must be set"
    exit 1
fi

if [ -z "${DEPLOY_DIR}" ]; then
    echo "ERROR: DEPLOY_DIR must be set"
    exit 1
fi

POOL_PREFIX="${NAMESPACE}-"

echo "=========================================="
echo "Generating MetalLB pool annotation patches"
echo "=========================================="
echo "Namespace: ${NAMESPACE}"
echo "Pool prefix: ${POOL_PREFIX}"
echo "Output: ${DEPLOY_DIR}/metallb-pool-patches.yaml"
echo "=========================================="

cat > ${DEPLOY_DIR}/metallb-pool-patches.yaml <<'EOF'
# Kustomize patches for OpenStack service MetalLB pool annotations
# These patches update the metallb.universe.tf/address-pool annotation
# to use namespace-prefixed pool names for multi-RHOSO deployments

# NOTE: These patches target the OpenStackControlPlane CR
# The actual services are created by the OpenStack operators based on these templates

---
# Patch DNSMasq service annotations
- op: add
  path: /spec/dns/template/override/service/metadata/annotations
  value:
    metallb.universe.tf/address-pool: ${POOL_PREFIX}ctlplane
    metallb.universe.tf/allow-shared-ip: ${POOL_PREFIX}ctlplane

---
# Patch Keystone internal service
- op: add
  path: /spec/keystone/template/override/service/internal/metadata/annotations
  value:
    metallb.universe.tf/address-pool: ${POOL_PREFIX}internalapi
    metallb.universe.tf/allow-shared-ip: ${POOL_PREFIX}internalapi

---
# Patch Glance internal service
- op: add
  path: /spec/glance/template/glanceAPIs/default/override/service/internal/metadata/annotations
  value:
    metallb.universe.tf/address-pool: ${POOL_PREFIX}internalapi
    metallb.universe.tf/allow-shared-ip: ${POOL_PREFIX}internalapi

---
# Patch Placement internal service
- op: add
  path: /spec/placement/template/override/service/internal/metadata/annotations
  value:
    metallb.universe.tf/address-pool: ${POOL_PREFIX}internalapi
    metallb.universe.tf/allow-shared-ip: ${POOL_PREFIX}internalapi

---
# Patch Neutron internal service
- op: add
  path: /spec/neutron/template/override/service/internal/metadata/annotations
  value:
    metallb.universe.tf/address-pool: ${POOL_PREFIX}internalapi
    metallb.universe.tf/allow-shared-ip: ${POOL_PREFIX}internalapi

---
# Patch Nova API internal service
- op: add
  path: /spec/nova/template/apiServiceTemplate/override/service/internal/metadata/annotations
  value:
    metallb.universe.tf/address-pool: ${POOL_PREFIX}internalapi
    metallb.universe.tf/allow-shared-ip: ${POOL_PREFIX}internalapi

---
# Patch Nova Metadata internal service
- op: add
  path: /spec/nova/template/metadataServiceTemplate/override/service/metadata/annotations
  value:
    metallb.universe.tf/address-pool: ${POOL_PREFIX}internalapi
    metallb.universe.tf/allow-shared-ip: ${POOL_PREFIX}internalapi

---
# Patch Cinder API internal service
- op: add
  path: /spec/cinder/template/cinderAPI/override/service/internal/metadata/annotations
  value:
    metallb.universe.tf/address-pool: ${POOL_PREFIX}internalapi
    metallb.universe.tf/allow-shared-ip: ${POOL_PREFIX}internalapi

---
# Patch Swift internal service
- op: add
  path: /spec/swift/template/swiftProxy/override/service/internal/metadata/annotations
  value:
    metallb.universe.tf/address-pool: ${POOL_PREFIX}internalapi
    metallb.universe.tf/allow-shared-ip: ${POOL_PREFIX}internalapi

---
# Patch RabbitMQ service
- op: add
  path: /spec/rabbitmq/templates/rabbitmq/override/service/metadata/annotations
  value:
    metallb.universe.tf/address-pool: ${POOL_PREFIX}internalapi
    metallb.universe.tf/allow-shared-ip: ${POOL_PREFIX}internalapi

---
# Patch RabbitMQ cell1 service
- op: add
  path: /spec/rabbitmq/templates/rabbitmq-cell1/override/service/metadata/annotations
  value:
    metallb.universe.tf/address-pool: ${POOL_PREFIX}internalapi
    metallb.universe.tf/allow-shared-ip: ${POOL_PREFIX}internalapi

---
# Patch OVN DBCluster NB service
- op: add
  path: /spec/ovn/template/ovnDBCluster/ovndbcluster-nb/override/service/metadata/annotations
  value:
    metallb.universe.tf/address-pool: ${POOL_PREFIX}internalapi
    metallb.universe.tf/allow-shared-ip: ${POOL_PREFIX}internalapi

---
# Patch OVN DBCluster SB service
- op: add
  path: /spec/ovn/template/ovnDBCluster/ovndbcluster-sb/override/service/metadata/annotations
  value:
    metallb.universe.tf/address-pool: ${POOL_PREFIX}internalapi
    metallb.universe.tf/allow-shared-ip: ${POOL_PREFIX}internalapi
EOF

# Replace ${POOL_PREFIX} with actual value
sed -i "s/\${POOL_PREFIX}/${POOL_PREFIX}/g" ${DEPLOY_DIR}/metallb-pool-patches.yaml

echo ""
echo "Patches generated successfully!"
echo "These patches will be applied during openstack_deploy"
