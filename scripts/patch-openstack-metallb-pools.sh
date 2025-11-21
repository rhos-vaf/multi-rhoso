#!/bin/bash
#
# Patch OpenStackControlPlane to use namespace-prefixed MetalLB pools
# This script patches the OpenStackControlPlane CR to update service annotations
#

set -e

if [ -z "${NAMESPACE}" ]; then
    echo "ERROR: NAMESPACE must be set"
    exit 1
fi

CONTROLPLANE_NAME=$(oc get openstackcontrolplane -n ${NAMESPACE} -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "${CONTROLPLANE_NAME}" ]; then
    echo "No OpenStackControlPlane found in namespace ${NAMESPACE}"
    echo "This script should be run AFTER openstack_deploy creates the control plane"
    exit 0
fi

POOL_PREFIX="${NAMESPACE}-"

echo "=========================================="
echo "Patching OpenStackControlPlane MetalLB pools"
echo "=========================================="
echo "Namespace: ${NAMESPACE}"
echo "ControlPlane: ${CONTROLPLANE_NAME}"
echo "Pool prefix: ${POOL_PREFIX}"
echo "=========================================="
echo ""

# Function to patch a service override (with LoadBalancer type)
patch_service() {
    local path=$1
    local pool=$2

    echo "Patching: ${path}"

    oc patch openstackcontrolplane ${CONTROLPLANE_NAME} -n ${NAMESPACE} --type=json -p="[
        {
            \"op\": \"add\",
            \"path\": \"${path}\",
            \"value\": {
                \"spec\": {
                    \"type\": \"LoadBalancer\"
                },
                \"metadata\": {
                    \"annotations\": {
                        \"metallb.universe.tf/address-pool\": \"${pool}\",
                        \"metallb.universe.tf/allow-shared-ip\": \"${pool}\"
                    }
                }
            }
        }
    ]" 2>/dev/null || echo "  (path may not exist or already set)"
}

# Function to patch DNS service (needs type: LoadBalancer)
patch_dns_service() {
    local pool=$1

    echo "Patching DNS service with LoadBalancer type"

    oc patch openstackcontrolplane ${CONTROLPLANE_NAME} -n ${NAMESPACE} --type=json -p="[
        {
            \"op\": \"add\",
            \"path\": \"/spec/dns/template/override/service\",
            \"value\": {
                \"spec\": {
                    \"type\": \"LoadBalancer\"
                },
                \"metadata\": {
                    \"annotations\": {
                        \"metallb.universe.tf/address-pool\": \"${pool}\",
                        \"metallb.universe.tf/allow-shared-ip\": \"${pool}\"
                    }
                }
            }
        }
    ]" 2>/dev/null || echo "  (path may not exist or already set)"
}

echo "Patching service annotations..."
echo ""

# Note: These patches may fail if the paths don't exist in your OpenStackControlPlane
# That's expected - not all services may be enabled

# DNS service needs special handling (type: LoadBalancer)
patch_dns_service "${POOL_PREFIX}ctlplane"
patch_service "/spec/keystone/template/override/service/internal" "${POOL_PREFIX}internalapi"
patch_service "/spec/glance/template/glanceAPIs/default/override/service/internal" "${POOL_PREFIX}internalapi"
patch_service "/spec/placement/template/override/service/internal" "${POOL_PREFIX}internalapi"
patch_service "/spec/neutron/template/override/service/internal" "${POOL_PREFIX}internalapi"
patch_service "/spec/nova/template/apiServiceTemplate/override/service/internal" "${POOL_PREFIX}internalapi"
patch_service "/spec/nova/template/metadataServiceTemplate/override/service" "${POOL_PREFIX}internalapi"
patch_service "/spec/cinder/template/cinderAPI/override/service/internal" "${POOL_PREFIX}internalapi"
patch_service "/spec/swift/template/swiftProxy/override/service/internal" "${POOL_PREFIX}internalapi"
patch_service "/spec/barbican/template/barbicanAPI/override/service/internal" "${POOL_PREFIX}internalapi"
# OVN Database services need LoadBalancer type
echo "Patching OVN database services with LoadBalancer type"
oc patch openstackcontrolplane ${CONTROLPLANE_NAME} -n ${NAMESPACE} --type=json -p="[
    {
        \"op\": \"add\",
        \"path\": \"/spec/ovn/template/ovnDBCluster/ovndbcluster-sb/dbPodService\",
        \"value\": {
            \"type\": \"LoadBalancer\",
            \"metadata\": {
                \"annotations\": {
                    \"metallb.universe.tf/address-pool\": \"${POOL_PREFIX}internalapi\",
                    \"metallb.universe.tf/allow-shared-ip\": \"${POOL_PREFIX}internalapi\"
                }
            }
        }
    },
    {
        \"op\": \"add\",
        \"path\": \"/spec/ovn/template/ovnDBCluster/ovndbcluster-nb/dbPodService\",
        \"value\": {
            \"type\": \"LoadBalancer\",
            \"metadata\": {
                \"annotations\": {
                    \"metallb.universe.tf/address-pool\": \"${POOL_PREFIX}internalapi\",
                    \"metallb.universe.tf/allow-shared-ip\": \"${POOL_PREFIX}internalapi\"
                }
            }
        }
    }
]" 2>/dev/null || echo "  (path may not exist or already set)"

# RabbitMQ services need LoadBalancer type
echo "Patching RabbitMQ services with LoadBalancer type"
oc patch openstackcontrolplane ${CONTROLPLANE_NAME} -n ${NAMESPACE} --type=json -p="[
    {
        \"op\": \"add\",
        \"path\": \"/spec/rabbitmq/templates/rabbitmq/override/service\",
        \"value\": {
            \"spec\": {
                \"type\": \"LoadBalancer\"
            },
            \"metadata\": {
                \"annotations\": {
                    \"metallb.universe.tf/address-pool\": \"${POOL_PREFIX}internalapi\",
                    \"metallb.universe.tf/allow-shared-ip\": \"${POOL_PREFIX}internalapi\"
                }
            }
        }
    },
    {
        \"op\": \"add\",
        \"path\": \"/spec/rabbitmq/templates/rabbitmq-cell1/override/service\",
        \"value\": {
            \"spec\": {
                \"type\": \"LoadBalancer\"
            },
            \"metadata\": {
                \"annotations\": {
                    \"metallb.universe.tf/address-pool\": \"${POOL_PREFIX}internalapi\",
                    \"metallb.universe.tf/allow-shared-ip\": \"${POOL_PREFIX}internalapi\"
                }
            }
        }
    }
]" 2>/dev/null || echo "  (path may not exist or already set)"

echo ""
echo "=========================================="
echo "Patching complete!"
echo "=========================================="
echo ""

# Wait a moment for the operator to reconcile
echo "Waiting 10 seconds for operator to reconcile..."
sleep 10

# Check for services stuck in <pending> and recreate them
echo ""
echo "Checking for LoadBalancer services stuck in <pending>..."
PENDING_SERVICES=$(oc get svc -n ${NAMESPACE} -o json | \
    jq -r '.items[] | select(.spec.type == "LoadBalancer" and .status.loadBalancer.ingress == null) | .metadata.name' 2>/dev/null || echo "")

if [ -n "$PENDING_SERVICES" ]; then
    echo "Found services stuck in <pending> state:"
    echo "$PENDING_SERVICES"
    echo ""
    echo "Recreating these services to apply MetalLB annotations..."

    for svc in $PENDING_SERVICES; do
        echo "  Deleting service: $svc"
        oc delete svc "$svc" -n ${NAMESPACE} --ignore-not-found=true
    done

    echo ""
    echo "Services deleted. The operator will recreate them with correct annotations."
    echo "Waiting 15 seconds for services to be recreated..."
    sleep 15

    echo ""
    echo "Recreated services:"
    oc get svc -n ${NAMESPACE} -o json | jq -r '.items[] | select(.spec.type == "LoadBalancer") | "\(.metadata.name)\t\(.spec.type)\t\(.status.loadBalancer.ingress[0].ip // "<pending>")"' | column -t
else
    echo "✅ All LoadBalancer services have IPs assigned!"
fi

echo ""
echo "=========================================="
echo "Final LoadBalancer services status:"
echo "=========================================="
oc get svc -n ${NAMESPACE} -o wide | grep -E "NAME|LoadBalancer" || echo "No LoadBalancer services found"
