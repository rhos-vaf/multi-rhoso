#!/bin/bash
#
# Patch NetConfig to use instance-specific network IP prefixes
# This script patches the NetConfig CR after deployment to update network CIDRs
#

set -e

if [ -z "${NAMESPACE}" ]; then
    echo "ERROR: NAMESPACE must be set"
    exit 1
fi

if [ -z "${NETWORK_INTERNALAPI_ADDRESS_PREFIX}" ]; then
    echo "ERROR: NETWORK_INTERNALAPI_ADDRESS_PREFIX must be set"
    exit 1
fi

if [ -z "${NETWORK_STORAGE_ADDRESS_PREFIX}" ]; then
    echo "ERROR: NETWORK_STORAGE_ADDRESS_PREFIX must be set"
    exit 1
fi

if [ -z "${NETWORK_TENANT_ADDRESS_PREFIX}" ]; then
    echo "ERROR: NETWORK_TENANT_ADDRESS_PREFIX must be set"
    exit 1
fi

if [ -z "${NETWORK_STORAGEMGMT_ADDRESS_PREFIX}" ]; then
    echo "ERROR: NETWORK_STORAGEMGMT_ADDRESS_PREFIX must be set"
    exit 1
fi

echo "=========================================="
echo "Patching NetConfig network IP prefixes"
echo "=========================================="
echo "Namespace: ${NAMESPACE}"
echo "InternalAPI: ${NETWORK_INTERNALAPI_ADDRESS_PREFIX}.0/24"
echo "Storage: ${NETWORK_STORAGE_ADDRESS_PREFIX}.0/24"
echo "Tenant: ${NETWORK_TENANT_ADDRESS_PREFIX}.0/24"
echo "StorageMgmt: ${NETWORK_STORAGEMGMT_ADDRESS_PREFIX}.0/24"
echo "=========================================="
echo ""

# Use sed to replace IP prefixes in the NetConfig YAML
# This approach is more reliable than JSON patch with unknown network indices

echo "Getting current NetConfig..."
oc get netconfigs netconfig -n ${NAMESPACE} -o yaml > /tmp/netconfig-${NAMESPACE}.yaml

echo "Patching IP prefixes with sed..."
sed -i "s/172\.17\.0/${NETWORK_INTERNALAPI_ADDRESS_PREFIX}/g" /tmp/netconfig-${NAMESPACE}.yaml
sed -i "s/172\.18\.0/${NETWORK_STORAGE_ADDRESS_PREFIX}/g" /tmp/netconfig-${NAMESPACE}.yaml
sed -i "s/172\.19\.0/${NETWORK_TENANT_ADDRESS_PREFIX}/g" /tmp/netconfig-${NAMESPACE}.yaml
sed -i "s/172\.20\.0/${NETWORK_STORAGEMGMT_ADDRESS_PREFIX}/g" /tmp/netconfig-${NAMESPACE}.yaml

echo "Applying patched NetConfig..."
oc apply -f /tmp/netconfig-${NAMESPACE}.yaml

echo "Cleaning up temporary file..."
rm -f /tmp/netconfig-${NAMESPACE}.yaml

echo ""
echo "=========================================="
echo "NetConfig patching complete!"
echo "=========================================="
echo ""
echo "Verify with:"
echo "  oc get netconfigs -n ${NAMESPACE} -o yaml | grep 'cidr:'"
