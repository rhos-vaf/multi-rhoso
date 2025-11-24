#!/bin/bash
#
# Copyright 2024 Red Hat Inc.
#
# Multi-RHOSO MetalLB configuration patcher
# This script patches existing IPAddressPools to add new IP ranges and namespaces
# instead of replacing them
#
set -e

if [ -z "${NAMESPACE}" ]; then
    echo "ERROR: NAMESPACE must be set for multi-RHOSO deployment"
    exit 1
fi

if [ -z "${CTLPLANE_METALLB_POOL}" ]; then
    echo "ERROR: CTLPLANE_METALLB_POOL must be set"
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

if [ -z "${NETWORK_DESIGNATE_EXT_ADDRESS_PREFIX}" ]; then
    echo "ERROR: NETWORK_DESIGNATE_EXT_ADDRESS_PREFIX must be set"
    exit 1
fi

if [ -z "${NNCP_INTERFACE}" ]; then
    echo "ERROR: NNCP_INTERFACE must be set"
    exit 1
fi

if [ -z "${NNCP_BRIDGE}" ]; then
    echo "ERROR: NNCP_BRIDGE must be set"
    exit 1
fi
echo "=========================================="
echo "Multi-RHOSO MetalLB Configuration"
echo "=========================================="
echo "Namespace: ${NAMESPACE}"
echo "CtlPlane Pool: ${CTLPLANE_METALLB_POOL}"
echo "InternalAPI: ${NETWORK_INTERNALAPI_ADDRESS_PREFIX}.80-.90"
echo "Storage: ${NETWORK_STORAGE_ADDRESS_PREFIX}.80-.90"
echo "Tenant: ${NETWORK_TENANT_ADDRESS_PREFIX}.80-.90"
echo "DesignateExt: ${NETWORK_DESIGNATE_EXT_ADDRESS_PREFIX}.80-.90"
echo "=========================================="
echo ""

# Check if this is the first RHOSO deployment by looking for any namespace-prefixed pools
echo "Detecting deployment state..."
EXISTING_PREFIXED_POOLS=$(oc get ipaddresspool -n metallb-system -o name 2>/dev/null | grep -E "/-" || true)

if [ -z "${EXISTING_PREFIXED_POOLS}" ]; then
    echo "✓ First RHOSO deployment detected (no namespace-prefixed pools exist)"

    # Check for non-prefixed pools (from upstream single-instance deployments)
    echo "Checking for conflicting non-prefixed MetalLB pools..."
    NON_PREFIXED_POOLS=$(oc get ipaddresspool -n metallb-system -o name 2>/dev/null | grep -E "/(ctlplane|internalapi|storage|tenant|designateext|storagemgmt)$" || true)

    if [ -n "${NON_PREFIXED_POOLS}" ]; then
        echo "⚠️  WARNING: Found non-prefixed MetalLB pools from vanilla install_yamls:"
        echo "${NON_PREFIXED_POOLS}"
        echo ""
        echo "These pools will cause IP address conflicts with multi-RHOSO deployment."
        echo "Deleting non-prefixed pools (one-time cleanup)..."
        echo "${NON_PREFIXED_POOLS}" | xargs -r oc delete -n metallb-system --ignore-not-found=true

        # Also delete corresponding L2Advertisements
        echo "Deleting corresponding L2Advertisements..."
        oc delete l2advertisement ctlplane internalapi storage tenant designateext storagemgmt -n metallb-system --ignore-not-found=true 2>/dev/null || true

        echo "✅ Cleanup complete"
        echo ""
    else
        echo "✓ No non-prefixed pools found - clean state"
        echo ""
    fi
else
    echo "✓ Additional RHOSO deployment detected (namespace-prefixed pools already exist)"
    echo "✓ Skipping non-prefixed pool cleanup (already done by first deployment)"
    echo ""
fi

# Function to patch or create IPAddressPool
patch_or_create_pool() {
    local pool_name=$1
    local address_range=$2
    local auto_assign=${3:-true}

    if oc get ipaddresspool "${pool_name}" -n metallb-system &>/dev/null; then
        echo "Pool '${pool_name}' exists - patching..."

        # Get current addresses
        current_addresses=$(oc get ipaddresspool "${pool_name}" -n metallb-system -o jsonpath='{.spec.addresses}')

        # Check if this address range already exists
        if echo "${current_addresses}" | grep -q "${address_range}"; then
            echo "  Address range ${address_range} already exists in pool ${pool_name}"
        else
            echo "  Adding address range: ${address_range}"
            oc patch ipaddresspool "${pool_name}" -n metallb-system --type=json -p="[
                {\"op\": \"add\", \"path\": \"/spec/addresses/-\", \"value\": \"${address_range}\"}
            ]"
        fi

        # Check if namespace is already in serviceAllocation
        current_namespaces=$(oc get ipaddresspool "${pool_name}" -n metallb-system -o jsonpath='{.spec.serviceAllocation.namespaces}' 2>/dev/null || echo "")

        if echo "${current_namespaces}" | grep -q "${NAMESPACE}"; then
            echo "  Namespace ${NAMESPACE} already in serviceAllocation"
        else
            echo "  Adding namespace: ${NAMESPACE}"
            # Check if serviceAllocation exists by looking for non-empty output
            service_allocation=$(oc get ipaddresspool "${pool_name}" -n metallb-system -o jsonpath='{.spec.serviceAllocation}' 2>/dev/null)
            if [ -n "${service_allocation}" ]; then
                # serviceAllocation exists, add namespace to existing list
                oc patch ipaddresspool "${pool_name}" -n metallb-system --type=json -p="[
                    {\"op\": \"add\", \"path\": \"/spec/serviceAllocation/namespaces/-\", \"value\": \"${NAMESPACE}\"}
                ]"
            else
                # serviceAllocation doesn't exist, create it with namespace
                oc patch ipaddresspool "${pool_name}" -n metallb-system --type=json -p="[
                    {\"op\": \"add\", \"path\": \"/spec/serviceAllocation\", \"value\": {\"namespaces\": [\"${NAMESPACE}\"]}}
                ]"
            fi
        fi
    else
        echo "Pool '${pool_name}' doesn't exist - creating..."
        cat <<EOF | oc apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: ${pool_name}
  namespace: metallb-system
spec:
  autoAssign: ${auto_assign}
  addresses:
  - ${address_range}
  serviceAllocation:
    namespaces:
    - ${NAMESPACE}
EOF
    fi
}

# Function to create L2Advertisement if it doesn't exist
create_l2adv_if_missing() {
    local adv_name=$1
    local pool_name=$2
    local interface=$3

    if oc get l2advertisement "${adv_name}" -n metallb-system &>/dev/null; then
        echo "L2Advertisement '${adv_name}' already exists - skipping"
    else
        echo "Creating L2Advertisement: ${adv_name}"
        cat <<EOF | oc apply -f -
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: ${adv_name}
  namespace: metallb-system
spec:
  ipAddressPools:
  - ${pool_name}
  interfaces:
  - ${interface}
EOF
    fi
}

echo "Step 1: Configuring IPAddressPools..."
echo "--------------------------------------"
patch_or_create_pool "${NAMESPACE}-ctlplane" "${CTLPLANE_METALLB_POOL}" "true"
patch_or_create_pool "${NAMESPACE}-internalapi" "${NETWORK_INTERNALAPI_ADDRESS_PREFIX}.80-${NETWORK_INTERNALAPI_ADDRESS_PREFIX}.90" "true"
patch_or_create_pool "${NAMESPACE}-storage" "${NETWORK_STORAGE_ADDRESS_PREFIX}.80-${NETWORK_STORAGE_ADDRESS_PREFIX}.90" "true"
patch_or_create_pool "${NAMESPACE}-tenant" "${NETWORK_TENANT_ADDRESS_PREFIX}.80-${NETWORK_TENANT_ADDRESS_PREFIX}.90" "true"
patch_or_create_pool "${NAMESPACE}-designateext" "${NETWORK_DESIGNATE_EXT_ADDRESS_PREFIX}.80-${NETWORK_DESIGNATE_EXT_ADDRESS_PREFIX}.90" "false"

echo ""
echo "Step 2: Configuring L2Advertisements..."
echo "--------------------------------------"
create_l2adv_if_missing "${NAMESPACE}-ctlplane" "${NAMESPACE}-ctlplane" "${NNCP_BRIDGE}"
create_l2adv_if_missing "${NAMESPACE}-internalapi" "${NAMESPACE}-internalapi" "${NNCP_INTERFACE}.20"
create_l2adv_if_missing "${NAMESPACE}-storage" "${NAMESPACE}-storage" "${NNCP_INTERFACE}.21"
create_l2adv_if_missing "${NAMESPACE}-tenant" "${NAMESPACE}-tenant" "${NNCP_INTERFACE}.22"
create_l2adv_if_missing "${NAMESPACE}-designateext" "${NAMESPACE}-designateext" "${NNCP_INTERFACE}.26"

echo ""
echo "=========================================="
echo "Configuration complete!"
echo "=========================================="
echo ""
echo "Verification:"
oc get ipaddresspool -n metallb-system | grep "${NAMESPACE}-"
echo ""
echo "Checking namespace scoping for ${NAMESPACE}-internalapi pool:"
oc get ipaddresspool "${NAMESPACE}-internalapi" -n metallb-system -o jsonpath='{.spec.serviceAllocation.namespaces}' | jq .
echo ""
