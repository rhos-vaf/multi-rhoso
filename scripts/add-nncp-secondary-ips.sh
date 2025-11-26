#!/bin/bash
#
# Add secondary IP addresses to CRC node VLAN interfaces
# This is required when deploying multiple RHOSO instances that share the same VLANs
# but use different IP subnets (e.g., openstack uses 172.17.0.x, openstack2 uses 172.27.0.x)
#
# Usage: bash scripts/add-nncp-secondary-ips.sh
#
# This script reads environment variables to determine which secondary IPs to add:
# - NETWORK_INTERNALAPI_ADDRESS_PREFIX
# - NETWORK_STORAGE_ADDRESS_PREFIX
# - NETWORK_TENANT_ADDRESS_PREFIX
# - NETWORK_STORAGEMGMT_ADDRESS_PREFIX
#

set -e

if [ -z "${NAMESPACE}" ]; then
    echo "ERROR: NAMESPACE must be set"
    echo "Please source your instance config file first (e.g., source config/multi-rhoso/rhoso2-config.env)"
    exit 1
fi

if [ -z "${NETWORK_INTERNALAPI_ADDRESS_PREFIX}" ]; then
    echo "ERROR: NETWORK_INTERNALAPI_ADDRESS_PREFIX must be set"
    exit 1
fi

# Default NNCP name (can be overridden)
NNCP_NAME=${NNCP_NAME:-enp6s0-crc}

echo "=========================================="
echo "Adding Secondary IPs to NNCP"
echo "=========================================="
echo "Namespace: ${NAMESPACE}"
echo "NNCP: ${NNCP_NAME}"
echo "InternalAPI: ${NETWORK_INTERNALAPI_ADDRESS_PREFIX}.5/24"
echo "Storage: ${NETWORK_STORAGE_ADDRESS_PREFIX}.5/24"
echo "Tenant: ${NETWORK_TENANT_ADDRESS_PREFIX}.5/24"
echo "StorageMgmt: ${NETWORK_STORAGEMGMT_ADDRESS_PREFIX}.5/24"
echo "Designate: ${NETWORK_DESIGNATE_ADDRESS_PREFIX}.5/24"
echo "DesignateExt: ${NETWORK_DESIGNATE_EXT_ADDRESS_PREFIX}.5/24"
echo "=========================================="
echo ""

# Check if NNCP exists
if ! oc get nncp ${NNCP_NAME} &>/dev/null; then
    echo "ERROR: NNCP ${NNCP_NAME} not found"
    echo "Available NNCPs:"
    oc get nncp
    exit 1
fi

# Check if secondary IPs already exist
echo "Checking if secondary IPs already exist..."

# Get current IPs from all VLAN interfaces
INTERNALAPI_IPS=$(oc get nncp ${NNCP_NAME} -o jsonpath='{.spec.desiredState.interfaces[0].ipv4.address[*].ip}' 2>/dev/null || echo "")
STORAGE_IPS=$(oc get nncp ${NNCP_NAME} -o jsonpath='{.spec.desiredState.interfaces[1].ipv4.address[*].ip}' 2>/dev/null || echo "")
TENANT_IPS=$(oc get nncp ${NNCP_NAME} -o jsonpath='{.spec.desiredState.interfaces[2].ipv4.address[*].ip}' 2>/dev/null || echo "")
STORAGEMGMT_IPS=$(oc get nncp ${NNCP_NAME} -o jsonpath='{.spec.desiredState.interfaces[3].ipv4.address[*].ip}' 2>/dev/null || echo "")
DESIGNATE_IPS=$(oc get nncp ${NNCP_NAME} -o jsonpath='{.spec.desiredState.interfaces[6].ipv4.address[*].ip}' 2>/dev/null || echo "")
DESIGNATE_EXT_IPS=$(oc get nncp ${NNCP_NAME} -o jsonpath='{.spec.desiredState.interfaces[7].ipv4.address[*].ip}' 2>/dev/null || echo "")

# Check each network
INTERNALAPI_EXISTS=false
STORAGE_EXISTS=false
TENANT_EXISTS=false
STORAGEMGMT_EXISTS=false
DESIGNATE_EXISTS=false
DESIGNATE_EXT_EXISTS=false

if echo "$INTERNALAPI_IPS" | grep -q "${NETWORK_INTERNALAPI_ADDRESS_PREFIX}.5"; then
    echo "✓ InternalAPI: ${NETWORK_INTERNALAPI_ADDRESS_PREFIX}.5 already exists on enp6s0.20"
    INTERNALAPI_EXISTS=true
else
    echo "○ InternalAPI: ${NETWORK_INTERNALAPI_ADDRESS_PREFIX}.5 needs to be added"
fi

if echo "$STORAGE_IPS" | grep -q "${NETWORK_STORAGE_ADDRESS_PREFIX}.5"; then
    echo "✓ Storage: ${NETWORK_STORAGE_ADDRESS_PREFIX}.5 already exists on enp6s0.21"
    STORAGE_EXISTS=true
else
    echo "○ Storage: ${NETWORK_STORAGE_ADDRESS_PREFIX}.5 needs to be added"
fi

if echo "$TENANT_IPS" | grep -q "${NETWORK_TENANT_ADDRESS_PREFIX}.5"; then
    echo "✓ Tenant: ${NETWORK_TENANT_ADDRESS_PREFIX}.5 already exists on enp6s0.22"
    TENANT_EXISTS=true
else
    echo "○ Tenant: ${NETWORK_TENANT_ADDRESS_PREFIX}.5 needs to be added"
fi

if echo "$STORAGEMGMT_IPS" | grep -q "${NETWORK_STORAGEMGMT_ADDRESS_PREFIX}.5"; then
    echo "✓ StorageMgmt: ${NETWORK_STORAGEMGMT_ADDRESS_PREFIX}.5 already exists on enp6s0.23"
    STORAGEMGMT_EXISTS=true
else
    echo "○ StorageMgmt: ${NETWORK_STORAGEMGMT_ADDRESS_PREFIX}.5 needs to be added"
fi

if echo "$DESIGNATE_IPS" | grep -q "${NETWORK_DESIGNATE_ADDRESS_PREFIX}.5"; then
    echo "✓ Designate: ${NETWORK_DESIGNATE_ADDRESS_PREFIX}.5 already exists on enp6s0.25"
    DESIGNATE_EXISTS=true
else
    echo "○ Designate: ${NETWORK_DESIGNATE_ADDRESS_PREFIX}.5 needs to be added"
fi

if echo "$DESIGNATE_EXT_IPS" | grep -q "${NETWORK_DESIGNATE_EXT_ADDRESS_PREFIX}.5"; then
    echo "✓ DesignateExt: ${NETWORK_DESIGNATE_EXT_ADDRESS_PREFIX}.5 already exists on enp6s0.26"
    DESIGNATE_EXT_EXISTS=true
else
    echo "○ DesignateExt: ${NETWORK_DESIGNATE_EXT_ADDRESS_PREFIX}.5 needs to be added"
fi

# If all IPs already exist, exit successfully
if [ "$INTERNALAPI_EXISTS" = true ] && [ "$STORAGE_EXISTS" = true ] && [ "$TENANT_EXISTS" = true ] && [ "$STORAGEMGMT_EXISTS" = true ] && [ "$DESIGNATE_EXISTS" = true ] && [ "$DESIGNATE_EXT_EXISTS" = true ]; then
    echo ""
    echo "=========================================="
    echo "✅ All secondary IPs already configured!"
    echo "=========================================="
    echo "No changes needed for namespace: ${NAMESPACE}"
    echo ""
    exit 0
fi

# Patch NNCP to add secondary IPs
echo ""
echo "Adding missing secondary IPs to VLAN interfaces..."

PATCH_OPS="["
FIRST_PATCH=true

# InternalAPI (enp6s0.20 - interface index 0)
if [ "$INTERNALAPI_EXISTS" = false ]; then
    if [ "$FIRST_PATCH" = false ]; then
        PATCH_OPS+=","
    fi
    PATCH_OPS+="
  {\"op\": \"add\", \"path\": \"/spec/desiredState/interfaces/0/ipv4/address/-\",
   \"value\": {\"ip\": \"${NETWORK_INTERNALAPI_ADDRESS_PREFIX}.5\", \"prefix-length\": 24}}"
    FIRST_PATCH=false
fi

# Storage (enp6s0.21 - interface index 1)
if [ "$STORAGE_EXISTS" = false ]; then
    if [ "$FIRST_PATCH" = false ]; then
        PATCH_OPS+=","
    fi
    PATCH_OPS+="
  {\"op\": \"add\", \"path\": \"/spec/desiredState/interfaces/1/ipv4/address/-\",
   \"value\": {\"ip\": \"${NETWORK_STORAGE_ADDRESS_PREFIX}.5\", \"prefix-length\": 24}}"
    FIRST_PATCH=false
fi

# Tenant (enp6s0.22 - interface index 2)
if [ "$TENANT_EXISTS" = false ]; then
    if [ "$FIRST_PATCH" = false ]; then
        PATCH_OPS+=","
    fi
    PATCH_OPS+="
  {\"op\": \"add\", \"path\": \"/spec/desiredState/interfaces/2/ipv4/address/-\",
   \"value\": {\"ip\": \"${NETWORK_TENANT_ADDRESS_PREFIX}.5\", \"prefix-length\": 24}}"
    FIRST_PATCH=false
fi

# StorageMgmt (enp6s0.23 - interface index 3)
if [ "$STORAGEMGMT_EXISTS" = false ]; then
    if [ "$FIRST_PATCH" = false ]; then
        PATCH_OPS+=","
    fi
    PATCH_OPS+="
  {\"op\": \"add\", \"path\": \"/spec/desiredState/interfaces/3/ipv4/address/-\",
   \"value\": {\"ip\": \"${NETWORK_STORAGEMGMT_ADDRESS_PREFIX}.5\", \"prefix-length\": 24}}"
    FIRST_PATCH=false
fi

# Designate (enp6s0.25 - interface index 6)
if [ "$DESIGNATE_EXISTS" = false ]; then
    if [ "$FIRST_PATCH" = false ]; then
        PATCH_OPS+=","
    fi
    PATCH_OPS+="
  {\"op\": \"add\", \"path\": \"/spec/desiredState/interfaces/6/ipv4/address/-\",
   \"value\": {\"ip\": \"${NETWORK_DESIGNATE_ADDRESS_PREFIX}.5\", \"prefix-length\": 24}}"
    FIRST_PATCH=false
fi

# DesignateExt (enp6s0.26 - interface index 7)
if [ "$DESIGNATE_EXT_EXISTS" = false ]; then
    if [ "$FIRST_PATCH" = false ]; then
        PATCH_OPS+=","
    fi
    PATCH_OPS+="
  {\"op\": \"add\", \"path\": \"/spec/desiredState/interfaces/7/ipv4/address/-\",
   \"value\": {\"ip\": \"${NETWORK_DESIGNATE_EXT_ADDRESS_PREFIX}.5\", \"prefix-length\": 24}}"
    FIRST_PATCH=false
fi

PATCH_OPS+="]"

echo "Applying NNCP patch..."
oc patch nncp ${NNCP_NAME} --type=json -p="$PATCH_OPS"

echo ""
echo "Waiting for NNCP to be configured (30 seconds)..."
sleep 30

# Verify configuration
NNCP_STATUS=$(oc get nncp ${NNCP_NAME} -o jsonpath='{.status.conditions[?(@.type=="Available")].status}')
if [ "$NNCP_STATUS" == "True" ]; then
    echo "✅ NNCP successfully configured"
else
    echo "⚠️  NNCP status: $(oc get nncp ${NNCP_NAME} -o jsonpath='{.status.conditions[?(@.type=="Available")].reason}')"
    echo "Run 'oc get nncp ${NNCP_NAME}' to check status"
fi

echo ""
echo "=========================================="
echo "Verifying IPs on CRC Node"
echo "=========================================="
echo ""

echo "VLAN 20 (InternalAPI - enp6s0.20):"
oc -n default debug node/crc -- chroot /host ip addr show enp6s0.20 2>/dev/null | grep "inet " | sed 's/^/    /' || echo "    Failed to get IPs"
echo ""

echo "VLAN 21 (Storage - enp6s0.21):"
oc -n default debug node/crc -- chroot /host ip addr show enp6s0.21 2>/dev/null | grep "inet " | sed 's/^/    /' || echo "    Failed to get IPs"
echo ""

echo "VLAN 22 (Tenant - enp6s0.22):"
oc -n default debug node/crc -- chroot /host ip addr show enp6s0.22 2>/dev/null | grep "inet " | sed 's/^/    /' || echo "    Failed to get IPs"
echo ""

echo "VLAN 23 (StorageMgmt - enp6s0.23):"
oc -n default debug node/crc -- chroot /host ip addr show enp6s0.23 2>/dev/null | grep "inet " | sed 's/^/    /' || echo "    Failed to get IPs"
echo ""

echo "VLAN 25 (Designate - enp6s0.25):"
oc -n default debug node/crc -- chroot /host ip addr show enp6s0.25 2>/dev/null | grep "inet " | sed 's/^/    /' || echo "    Failed to get IPs"
echo ""

echo "VLAN 26 (DesignateExt - enp6s0.26):"
oc -n default debug node/crc -- chroot /host ip addr show enp6s0.26 2>/dev/null | grep "inet " | sed 's/^/    /' || echo "    Failed to get IPs"

echo ""
echo "=========================================="
echo "Secondary IP addition complete!"
echo "=========================================="
echo ""
echo "Note: These secondary IPs allow MetalLB to advertise service IPs"
echo "from the ${NAMESPACE} network ranges on the same VLAN interfaces."
