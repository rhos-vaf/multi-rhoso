#!/bin/bash
#
# Patch NetConfig YAML file BEFORE deployment
# This script modifies the NetConfig YAML file that will be deployed
#

set -e

if [ -z "${NAMESPACE}" ]; then
    echo "ERROR: NAMESPACE must be set"
    exit 1
fi

if [ -z "${OUT}" ]; then
    echo "ERROR: OUT must be set"
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

NETCONFIG_FILE="${OUT}/${NAMESPACE}/infra/cr/network_v1beta1_netconfig.yaml"

if [ ! -f "${NETCONFIG_FILE}" ]; then
    echo "ERROR: NetConfig file not found: ${NETCONFIG_FILE}"
    exit 1
fi

echo "=========================================="
echo "Patching NetConfig YAML before deployment"
echo "=========================================="
echo "File: ${NETCONFIG_FILE}"
echo "InternalAPI: ${NETWORK_INTERNALAPI_ADDRESS_PREFIX}.0/24"
echo "Storage: ${NETWORK_STORAGE_ADDRESS_PREFIX}.0/24"
echo "Tenant: ${NETWORK_TENANT_ADDRESS_PREFIX}.0/24"
echo "StorageMgmt: ${NETWORK_STORAGEMGMT_ADDRESS_PREFIX}.0/24"
echo "=========================================="

# Patch IP prefixes in the NetConfig YAML file
sed -i "s/172\.17\.0/${NETWORK_INTERNALAPI_ADDRESS_PREFIX}/g" "${NETCONFIG_FILE}"
sed -i "s/172\.18\.0/${NETWORK_STORAGE_ADDRESS_PREFIX}/g" "${NETCONFIG_FILE}"
sed -i "s/172\.19\.0/${NETWORK_TENANT_ADDRESS_PREFIX}/g" "${NETCONFIG_FILE}"
sed -i "s/172\.20\.0/${NETWORK_STORAGEMGMT_ADDRESS_PREFIX}/g" "${NETCONFIG_FILE}"

echo "✅ NetConfig YAML patched successfully!"
