# Multi-RHOSO Deployment Makefile
#
# This Makefile orchestrates multi-instance RHOSO (Red Hat OpenStack Services on OpenShift)
# deployments using the upstream install_yamls repository.
#
# Usage:
#   1. Deploy shared infrastructure once:
#      make infrastructure
#
#   2. Deploy first RHOSO instance:
#      source config/rhoso1.env && make instance
#
#   3. Deploy additional instances:
#      source config/rhoso2.env && make instance
#
# Or run individual steps:
#      source config/rhoso1.env && make nncp
#      source config/rhoso1.env && make netattach
#      source config/rhoso1.env && make metallb-config
#      source config/rhoso1.env && make controlplane
#      source config/rhoso1.env && make dataplane
#
# See README.md for detailed documentation.

# Upstream install_yamls directory
INSTALL_YAMLS_DIR := $(CURDIR)/install_yamls

# Shared output directory for both wrapper and upstream
OUT := $(CURDIR)/out
export OUT

# Configuration directory
CONFIG_DIR := $(CURDIR)/config

# Common configuration shared across all RHOSO instances
# These can be overridden by setting environment variables before running make
OPERATOR_NAMESPACE ?= openstack-operators
NNCP_INTERFACE ?= enp6s0
NNCP_BRIDGE ?= ospbr
NETWORK_VLAN_START ?= 20
NETWORK_VLAN_STEP ?= 1
NETWORK_MTU ?= 1500
NNCP_CTLPLANE_IP_ADDRESS_PREFIX ?= 192.168.122
NNCP_DNS_SERVER ?= 192.168.122.1
NNCP_GATEWAY ?= 192.168.122.1
DATAPLANE_TOTAL_NODES ?= 1
DATAPLANE_SSHD_ALLOWED_RANGES ?= ['192.168.122.0/24']
NETWORK_ISOLATION ?= true
NETWORK_ISOLATION_USE_DEFAULT_NETWORK ?= true
NETWORK_ISOLATION_IPV4 ?= true
NETWORK_ISOLATION_IPV6 ?= false
TIMEOUT ?= 500s

# CRC (OpenShift local cluster) configuration
CRC_VERSION ?= 2.41.0
PULL_SECRET ?= $(HOME)/pull-secret
CPUS ?= 32
MEMORY ?= 65536
DISK ?= 300

# Export common variables that are shared across all instances
export OPERATOR_NAMESPACE
export NNCP_INTERFACE
export NNCP_BRIDGE
export NETWORK_VLAN_START
export NETWORK_VLAN_STEP
export NETWORK_MTU
export NNCP_CTLPLANE_IP_ADDRESS_PREFIX
export NNCP_DNS_SERVER
export NNCP_GATEWAY
export DATAPLANE_TOTAL_NODES
export DATAPLANE_SSHD_ALLOWED_RANGES
export NETWORK_ISOLATION
export NETWORK_ISOLATION_USE_DEFAULT_NETWORK
export NETWORK_ISOLATION_IPV4
export NETWORK_ISOLATION_IPV6
export TIMEOUT
export CRC_VERSION
export PULL_SECRET
export CPUS
export MEMORY
export DISK

# CRITICAL: Export instance-specific network configuration variables
# These MUST be exported so they pass through to upstream install_yamls Makefile
# These are sourced from config files (rhoso1.env, rhoso2.env, etc.)
export NAMESPACE
export NETWORK_INTERNALAPI_ADDRESS_PREFIX
export NETWORK_STORAGE_ADDRESS_PREFIX
export NETWORK_TENANT_ADDRESS_PREFIX
export NETWORK_STORAGEMGMT_ADDRESS_PREFIX
export NETWORK_DESIGNATE_EXT_ADDRESS_PREFIX
export CTLPLANE_METALLB_POOL
export DATAPLANE_COMPUTE_IP
export DATAPLANE_COMPUTE_0_IP
export DATAPLANE_COMPUTE_0_NAME

# OpenStack operator image configuration
OPENSTACK_K8S_TAG ?= latest
OPENSTACK_IMG ?= quay.io/openstack-k8s-operators/openstack-operator-index:${OPENSTACK_K8S_TAG}

# OpenStack ControlPlane CR sample to use
OPENSTACK_CTLPLANE ?= config/samples/core_v1beta1_openstackcontrolplane_galera_network_isolation.yaml
export OPENSTACK_CTLPLANE

# Upstream repository
INSTALL_YAMLS_REPO := https://github.com/openstack-k8s-operators/install_yamls.git

# Default target - show help when running 'make' without arguments
.DEFAULT_GOAL := help

# Ensure install_yamls exists (clone if missing)
.PHONY: check-install-yamls
check-install-yamls:
	@if [ ! -d "$(INSTALL_YAMLS_DIR)" ]; then \
		echo "========================================"; \
		echo "install_yamls not found - cloning from upstream"; \
		echo "Repository: $(INSTALL_YAMLS_REPO)"; \
		echo "========================================"; \
		git clone $(INSTALL_YAMLS_REPO) $(INSTALL_YAMLS_DIR); \
		echo ""; \
		echo "✅ install_yamls cloned successfully"; \
		echo ""; \
	fi

# Verify NAMESPACE is set (minimal check for all targets)
.PHONY: check-namespace
check-namespace:
	@if [ -z "$(NAMESPACE)" ]; then \
		echo "❌ Error: NAMESPACE not set"; \
		echo ""; \
		echo "Please source a configuration file first:"; \
		echo "  source config/rhoso1.env && make <target>"; \
		echo "  source config/rhoso2.env && make <target>"; \
		exit 1; \
	fi

# Verify NNCP-specific variables
.PHONY: check-nncp-config
check-nncp-config: check-namespace
	@missing=""; \
	if [ -z "$(NETWORK_INTERNALAPI_ADDRESS_PREFIX)" ]; then missing="$$missing NETWORK_INTERNALAPI_ADDRESS_PREFIX"; fi; \
	if [ -z "$(NETWORK_STORAGE_ADDRESS_PREFIX)" ]; then missing="$$missing NETWORK_STORAGE_ADDRESS_PREFIX"; fi; \
	if [ -z "$(NETWORK_TENANT_ADDRESS_PREFIX)" ]; then missing="$$missing NETWORK_TENANT_ADDRESS_PREFIX"; fi; \
	if [ -z "$(NETWORK_STORAGEMGMT_ADDRESS_PREFIX)" ]; then missing="$$missing NETWORK_STORAGEMGMT_ADDRESS_PREFIX"; fi; \
	if [ -n "$$missing" ]; then \
		echo "❌ Error: Missing required variables for NNCP:"; \
		echo "$$missing" | tr ' ' '\n' | sed 's/^/  - /'; \
		exit 1; \
	fi

# Verify netattach-specific variables
.PHONY: check-netattach-config
check-netattach-config: check-namespace
	@missing=""; \
	if [ -z "$(NETWORK_INTERNALAPI_ADDRESS_PREFIX)" ]; then missing="$$missing NETWORK_INTERNALAPI_ADDRESS_PREFIX"; fi; \
	if [ -z "$(NETWORK_STORAGE_ADDRESS_PREFIX)" ]; then missing="$$missing NETWORK_STORAGE_ADDRESS_PREFIX"; fi; \
	if [ -z "$(NETWORK_TENANT_ADDRESS_PREFIX)" ]; then missing="$$missing NETWORK_TENANT_ADDRESS_PREFIX"; fi; \
	if [ -z "$(NETWORK_STORAGEMGMT_ADDRESS_PREFIX)" ]; then missing="$$missing NETWORK_STORAGEMGMT_ADDRESS_PREFIX"; fi; \
	if [ -n "$$missing" ]; then \
		echo "❌ Error: Missing required variables for network attachments:"; \
		echo "$$missing" | tr ' ' '\n' | sed 's/^/  - /'; \
		exit 1; \
	fi

# Verify MetalLB-specific variables
.PHONY: check-metallb-config
check-metallb-config: check-namespace
	@missing=""; \
	if [ -z "$(CTLPLANE_METALLB_POOL)" ]; then missing="$$missing CTLPLANE_METALLB_POOL"; fi; \
	if [ -z "$(NETWORK_INTERNALAPI_ADDRESS_PREFIX)" ]; then missing="$$missing NETWORK_INTERNALAPI_ADDRESS_PREFIX"; fi; \
	if [ -z "$(NETWORK_STORAGE_ADDRESS_PREFIX)" ]; then missing="$$missing NETWORK_STORAGE_ADDRESS_PREFIX"; fi; \
	if [ -z "$(NETWORK_TENANT_ADDRESS_PREFIX)" ]; then missing="$$missing NETWORK_TENANT_ADDRESS_PREFIX"; fi; \
	if [ -z "$(NETWORK_DESIGNATE_EXT_ADDRESS_PREFIX)" ]; then missing="$$missing NETWORK_DESIGNATE_EXT_ADDRESS_PREFIX"; fi; \
	if [ -n "$$missing" ]; then \
		echo "❌ Error: Missing required variables for MetalLB:"; \
		echo "$$missing" | tr ' ' '\n' | sed 's/^/  - /'; \
		exit 1; \
	fi

# Verify EDPM-specific variables
.PHONY: check-edpm-config
check-edpm-config: check-namespace
	@missing=""; \
	if [ -z "$(DATAPLANE_COMPUTE_IP)" ]; then missing="$$missing DATAPLANE_COMPUTE_IP"; fi; \
	if [ -z "$(DATAPLANE_COMPUTE_0_IP)" ]; then missing="$$missing DATAPLANE_COMPUTE_0_IP"; fi; \
	if [ -z "$(DATAPLANE_COMPUTE_0_NAME)" ]; then missing="$$missing DATAPLANE_COMPUTE_0_NAME"; fi; \
	if [ -n "$$missing" ]; then \
		echo "❌ Error: Missing required variables for EDPM:"; \
		echo "$$missing" | tr ' ' '\n' | sed 's/^/  - /'; \
		exit 1; \
	fi

# Verify all required variables for full instance deployment
.PHONY: check-instance-config
check-instance-config: check-namespace
	@missing=""; \
	if [ -z "$(NETWORK_INTERNALAPI_ADDRESS_PREFIX)" ]; then missing="$$missing NETWORK_INTERNALAPI_ADDRESS_PREFIX"; fi; \
	if [ -z "$(NETWORK_STORAGE_ADDRESS_PREFIX)" ]; then missing="$$missing NETWORK_STORAGE_ADDRESS_PREFIX"; fi; \
	if [ -z "$(NETWORK_TENANT_ADDRESS_PREFIX)" ]; then missing="$$missing NETWORK_TENANT_ADDRESS_PREFIX"; fi; \
	if [ -z "$(NETWORK_STORAGEMGMT_ADDRESS_PREFIX)" ]; then missing="$$missing NETWORK_STORAGEMGMT_ADDRESS_PREFIX"; fi; \
	if [ -z "$(CTLPLANE_METALLB_POOL)" ]; then missing="$$missing CTLPLANE_METALLB_POOL"; fi; \
	if [ -z "$(DATAPLANE_COMPUTE_IP)" ]; then missing="$$missing DATAPLANE_COMPUTE_IP"; fi; \
	if [ -z "$(DATAPLANE_COMPUTE_0_IP)" ]; then missing="$$missing DATAPLANE_COMPUTE_0_IP"; fi; \
	if [ -z "$(DATAPLANE_COMPUTE_0_NAME)" ]; then missing="$$missing DATAPLANE_COMPUTE_0_NAME"; fi; \
	if [ -n "$$missing" ]; then \
		echo "❌ Error: Missing required configuration variables:"; \
		echo "$$missing" | tr ' ' '\n' | sed 's/^/  - /'; \
		echo ""; \
		echo "Please ensure your config file sets all required variables."; \
		echo ""; \
		echo "Example config file (config/openstack3.env):"; \
		echo "  export NAMESPACE=openstack3"; \
		echo "  export NETWORK_INTERNALAPI_ADDRESS_PREFIX=172.37.0"; \
		echo "  export NETWORK_STORAGE_ADDRESS_PREFIX=172.39.0"; \
		echo "  export NETWORK_TENANT_ADDRESS_PREFIX=172.41.0"; \
		echo "  export NETWORK_STORAGEMGMT_ADDRESS_PREFIX=172.42.0"; \
		echo "  export CTLPLANE_METALLB_POOL=192.168.122.130-192.168.122.140"; \
		echo "  export DATAPLANE_COMPUTE_IP=192.168.122.102"; \
		echo "  export DATAPLANE_COMPUTE_0_IP=192.168.122.102"; \
		echo "  export DATAPLANE_COMPUTE_0_NAME=edpm-compute-2"; \
		exit 1; \
	fi
	@echo "✅ Instance configuration validated for namespace: $(NAMESPACE)"

# Help target
.PHONY: help
help: ## Show this help message
	@echo "Multi-RHOSO Deployment Targets:"
	@echo ""
	@echo "CRC Installation (optional - run once if you don't have OpenShift):"
	@echo "  make crc                - Install and configure CRC cluster"
	@echo ""
	@echo "Shared Infrastructure (run once):"
	@echo "  make infrastructure     - Deploy all shared infrastructure components"
	@echo ""
	@echo "  Or run individual infrastructure targets once:"
	@echo "    make openstack        - Install operators (NMState, MetalLB, Cert Manager, OpenStack)"
	@echo "    make openstack-init   - Initialize OpenStack operators"
	@echo "    make storage          - Create persistent volumes"
	@echo ""
	@echo "RHOSO Instance Deployment (after sourcing config):"
	@echo "  source config/rhoso1.env && make instance       - Deploy complete instance"
	@echo ""
	@echo "  Or run individual instance targets:"
	@echo "    source config/rhoso1.env && make nncp           - Configure NNCP"
	@echo "    source config/rhoso1.env && make namespace      - Create namespace"
	@echo "    source config/rhoso1.env && make netattach      - Create network attachments"
	@echo "    source config/rhoso1.env && make metallb-config - Configure MetalLB pools"
	@echo "    source config/rhoso1.env && make controlplane   - Deploy control plane"
	@echo "    source config/rhoso1.env && make dataplane      - Deploy data plane compute"
	@echo ""
	@echo "Verification:"
	@echo "  make verify-nncp                        - Verify NNCP configuration and IPs"
	@echo "  source config/rhoso1.env && make verify - Verify instance deployment"
	@echo ""
	@echo "Cleanup:"
	@echo "  source config/rhoso1.env && make clean  - Remove instance"
	@echo "  make clean-all                          - Remove all instances and infrastructure"
	@echo ""
	@echo "Examples:"
	@echo "  # Deploy instance 1"
	@echo "  source config/rhoso1.env && make instance"
	@echo ""
	@echo "  # Deploy instance 2"
	@echo "  source config/rhoso2.env && make instance"
	@echo ""
	@echo "Note: You can use ANY namespace name (rhoso1, democluster, production, etc.)"
	@echo "      The Makefile automatically detects whether to generate NNCP or add IPs."

##############################################################################
# OPENSHIFT INSTALLATION
##############################################################################

.PHONY: download_tools
download_tools: check-install-yamls ## Download required development tools (kubectl, kustomize, oc, etc.)
	@echo "=========================================="
	@echo "Downloading Development Tools"
	@echo "=========================================="
	$(MAKE) -C $(INSTALL_YAMLS_DIR)/devsetup download_tools

.PHONY: openshift
openshift: check-install-yamls ## Install and configure OpenShift (CRC local cluster)
	@echo "=========================================="
	@echo "Downloading Development Tools"
	@echo "=========================================="
	@$(MAKE) -C $(INSTALL_YAMLS_DIR)/devsetup download_tools
	@echo ""
	@echo "=========================================="
	@echo "Installing OpenShift (CRC)"
	@echo "=========================================="
	@echo "CRC Version: $(CRC_VERSION)"
	@echo "Pull Secret: $(PULL_SECRET)"
	@echo "CPUs: $(CPUS)"
	@echo "Memory: $(MEMORY) MB"
	@echo "Disk: $(DISK) GB"
	@echo "=========================================="
	@if [ ! -f "$(PULL_SECRET)" ]; then \
		echo "❌ Error: Pull secret not found at $(PULL_SECRET)"; \
		echo ""; \
		echo "Please download your pull secret from:"; \
		echo "  https://console.redhat.com/openshift/create/local"; \
		echo ""; \
		echo "And save it to: $(PULL_SECRET)"; \
		exit 1; \
	fi
	$(MAKE) -C $(INSTALL_YAMLS_DIR)/devsetup crc CRC_VERSION=$(CRC_VERSION) PULL_SECRET="$(PULL_SECRET)" CPUS=$(CPUS) MEMORY=$(MEMORY) DISK=$(DISK)
	$(MAKE) -C $(INSTALL_YAMLS_DIR)/devsetup crc_attach_default_interface

##############################################################################
# SHARED INFRASTRUCTURE TARGETS (RUN ONCE)
##############################################################################

.PHONY: infrastructure
infrastructure: check-install-yamls nmstate metallb certmanager openstack openstack-init storage ## Deploy all shared infrastructure

.PHONY: nmstate
nmstate: check-install-yamls ## Install NMState operator (network interface configuration)
	@echo "=========================================="
	@echo "Installing NMState Operator"
	@echo "=========================================="
	$(MAKE) -C $(INSTALL_YAMLS_DIR) nmstate

.PHONY: metallb
metallb: check-install-yamls ## Install MetalLB operator (LoadBalancer IP allocation)
	@echo "=========================================="
	@echo "Installing MetalLB Operator"
	@echo "=========================================="
	$(MAKE) -C $(INSTALL_YAMLS_DIR) metallb

.PHONY: certmanager
certmanager: check-install-yamls ## Install Cert Manager operator (certificate management)
	@echo "=========================================="
	@echo "Installing Cert Manager Operator"
	@echo "=========================================="
	$(MAKE) -C $(INSTALL_YAMLS_DIR) certmanager

.PHONY: openstack
openstack: check-install-yamls ## Install OpenStack operators (skips NNCP, NMState, MetalLB)
	@echo "=========================================="
	@echo "Installing OpenStack Operators"
	@echo "=========================================="
	@echo "This will install:"
	@echo "  - Cert Manager operator (certificate management)"
	@echo "  - OpenStack operators (Nova, Neutron, Cinder, etc.)"
	@echo ""
	@echo "Note: NNCP, NMState, and MetalLB are installed separately"
	@echo "      and will be skipped during OpenStack operator installation"
	@echo "=========================================="
	@# Validate marketplace is ready
	$(MAKE) -C $(INSTALL_YAMLS_DIR) validate_marketplace
	@# Create the openstack-operators namespace
	$(MAKE) -C $(INSTALL_YAMLS_DIR) operator_namespace NAMESPACE=openstack-operators
	@# Generate OpenStack operator OLM files (without running dependencies)
	@cd $(INSTALL_YAMLS_DIR) && \
		NAMESPACE=openstack-operators \
		OPERATOR_NAMESPACE=openstack-operators \
		OPERATOR_NAME=openstack \
		OPERATOR_DIR=$(OUT)/openstack-operators/openstack/op \
		IMAGE=$(OPENSTACK_IMG) \
		bash scripts/gen-olm.sh
	@# Apply the OpenStack operator subscription
	@oc apply -f $(OUT)/openstack-operators/openstack/op

.PHONY: openstack-init
openstack-init: check-install-yamls ## Initialize OpenStack operators
	@echo "=========================================="
	@echo "Initializing OpenStack Operators"
	@echo "=========================================="
	$(MAKE) -C $(INSTALL_YAMLS_DIR) openstack_init

.PHONY: storage
storage: check-install-yamls ## Create persistent volumes for OpenStack
	@echo "=========================================="
	@echo "Creating Persistent Volumes (30 PVs)"
	@echo "=========================================="
	$(MAKE) -C $(INSTALL_YAMLS_DIR) crc_storage PV_NUM=30

##############################################################################
# RHOSO INSTANCE DEPLOYMENT (requires config sourced)
##############################################################################

.PHONY: instance
instance: check-install-yamls check-instance-config nncp namespace netattach metallb-config controlplane wait-controlplane dataplane ## Deploy complete RHOSO instance

.PHONY: nncp
nncp: check-install-yamls check-nncp-config ## Configure NNCP (generates for first instance, adds secondary IPs for others)
	@echo "=========================================="
	@echo "Configuring NNCP for namespace: $(NAMESPACE)"
	@# Check if this is the first RHOSO instance by detecting if NNCP already exists
	@if oc get nncp 2>/dev/null | grep -q .; then \
		echo "NNCP already exists - Adding secondary IPs only"; \
		echo "This is an additional RHOSO instance ($(NAMESPACE))"; \
		bash $(CURDIR)/scripts/add-nncp-secondary-ips.sh; \
	else \
		echo "No NNCP found - Generating NNCP with primary IPs"; \
		echo "This is the first RHOSO instance ($(NAMESPACE))"; \
		$(MAKE) -C $(INSTALL_YAMLS_DIR) nncp; \
	fi
	@echo "=========================================="

.PHONY: namespace
namespace: check-install-yamls check-namespace ## Create namespace
	@echo "=========================================="
	@echo "Creating Namespace: $(NAMESPACE)"
	@echo "=========================================="
	$(MAKE) -C $(INSTALL_YAMLS_DIR) namespace

.PHONY: netattach
netattach: check-install-yamls check-netattach-config ## Create network attachments
	@echo "=========================================="
	@echo "Creating Network Attachments for: $(NAMESPACE)"
	@echo "=========================================="
	$(MAKE) -C $(INSTALL_YAMLS_DIR) netattach

.PHONY: metallb-config
metallb-config: check-install-yamls check-metallb-config ## Configure MetalLB IP pools with namespace prefixes
	@echo "=========================================="
	@echo "Configuring MetalLB for: $(NAMESPACE)"
	@echo "CtlPlane Pool: $(CTLPLANE_METALLB_POOL)"
	@echo "=========================================="
	@# Use wrapper's script to create namespace-prefixed pools
	@# This ensures pool names match the annotations (e.g., openstack-internalapi)
	@NAMESPACE=$(NAMESPACE) \
		CTLPLANE_METALLB_POOL=$(CTLPLANE_METALLB_POOL) \
		NETWORK_INTERNALAPI_ADDRESS_PREFIX=$(NETWORK_INTERNALAPI_ADDRESS_PREFIX) \
		NETWORK_STORAGE_ADDRESS_PREFIX=$(NETWORK_STORAGE_ADDRESS_PREFIX) \
		NETWORK_TENANT_ADDRESS_PREFIX=$(NETWORK_TENANT_ADDRESS_PREFIX) \
		NETWORK_STORAGEMGMT_ADDRESS_PREFIX=$(NETWORK_STORAGEMGMT_ADDRESS_PREFIX) \
		NETWORK_DESIGNATE_EXT_ADDRESS_PREFIX=$(NETWORK_DESIGNATE_EXT_ADDRESS_PREFIX) \
		bash $(CURDIR)/scripts/patch-metallb-multi-rhoso.sh

.PHONY: controlplane
controlplane: check-install-yamls check-namespace ## Deploy OpenStack control plane with namespace-prefixed MetalLB pools
	@echo "=========================================="
	@echo "Deploying OpenStack Control Plane"
	@echo "Namespace: $(NAMESPACE)"
	@echo "Network Prefixes:"
	@echo "  InternalAPI: $(NETWORK_INTERNALAPI_ADDRESS_PREFIX).0/24"
	@echo "  Storage: $(NETWORK_STORAGE_ADDRESS_PREFIX).0/24"
	@echo "  Tenant: $(NETWORK_TENANT_ADDRESS_PREFIX).0/24"
	@echo "  StorageMgmt: $(NETWORK_STORAGEMGMT_ADDRESS_PREFIX).0/24"
	@echo "=========================================="
	@echo ""
	@echo "Step 1: Creating secrets (osp-secret)..."
	@# CRITICAL: Create secrets before deploying services
	@cd $(INSTALL_YAMLS_DIR) && $(MAKE) input NAMESPACE=$(NAMESPACE)
	@echo ""
	@echo "Step 2: Preparing all YAML files (NetConfig + OpenStackControlPlane)..."
	@# Call netconfig_deploy_prep ONCE to prepare the NetConfig YAML
	@cd $(INSTALL_YAMLS_DIR) && $(MAKE) netconfig_deploy_prep NAMESPACE=$(NAMESPACE)
	@echo ""
	@echo "Step 3: Patching NetConfig YAML with instance-specific IPs..."
	@NAMESPACE=$(NAMESPACE) \
		OUT=$(OUT) \
		NETWORK_INTERNALAPI_ADDRESS_PREFIX=$(NETWORK_INTERNALAPI_ADDRESS_PREFIX) \
		NETWORK_STORAGE_ADDRESS_PREFIX=$(NETWORK_STORAGE_ADDRESS_PREFIX) \
		NETWORK_TENANT_ADDRESS_PREFIX=$(NETWORK_TENANT_ADDRESS_PREFIX) \
		NETWORK_STORAGEMGMT_ADDRESS_PREFIX=$(NETWORK_STORAGEMGMT_ADDRESS_PREFIX) \
		bash $(CURDIR)/scripts/patch-netconfig-yaml.sh
	@echo ""
	@echo "Step 4: Deploying NetConfig (using patched YAML)..."
	@# Deploy NetConfig directly without calling netconfig_deploy
	@cd $(INSTALL_YAMLS_DIR) && DEPLOY_DIR=$(OUT)/$(NAMESPACE)/infra/cr bash scripts/operator-deploy-resources.sh
	@echo ""
	@echo "Step 5: Preparing OpenStackControlPlane YAML..."
	@# Call openstack_repo to clone the operator repo (needed for OpenStackControlPlane sample)
	@cd $(INSTALL_YAMLS_DIR) && $(MAKE) openstack_repo NAMESPACE=$(NAMESPACE)
	@# Manually prepare OpenStackControlPlane CR without cleanup
	@mkdir -p $(OUT)/$(NAMESPACE)/openstack/cr
	@cp $(OUT)/operator/openstack-operator/$(OPENSTACK_CTLPLANE) \
		$(OUT)/$(NAMESPACE)/openstack/cr/
	@# Generate kustomization for OpenStackControlPlane
	@cd $(INSTALL_YAMLS_DIR) && \
		NAMESPACE=$(NAMESPACE) \
		KIND=OpenStackControlPlane \
		SECRET=osp-secret \
		STORAGE_CLASS=local-storage \
		IPV4_ENABLED=true \
		CTLPLANE_IPV4_DNS_SERVER=$(NNCP_DNS_SERVER) \
		DEPLOY_DIR=$(OUT)/$(NAMESPACE)/openstack/cr \
		bash scripts/gen-service-kustomize.sh
	@echo ""
	@echo "Step 6: Deploying OpenStackControlPlane..."
	@cd $(INSTALL_YAMLS_DIR) && DEPLOY_DIR=$(OUT)/$(NAMESPACE)/openstack/cr bash scripts/operator-deploy-resources.sh
	@echo ""
	@echo "Step 7: Patching MetalLB pool annotations..."
	@NAMESPACE=$(NAMESPACE) bash $(CURDIR)/scripts/patch-openstack-metallb-pools.sh

.PHONY: wait-controlplane
wait-controlplane: check-namespace ## Wait for OpenStackControlPlane to be ready
	@echo "=========================================="
	@echo "Waiting for Control Plane to be Ready"
	@echo "Namespace: $(NAMESPACE)"
	@echo "=========================================="
	@echo "Waiting for OpenStackControlPlane to reach STATUS=True..."
	@timeout=1800; \
	elapsed=0; \
	while [ $$elapsed -lt $$timeout ]; do \
		status=$$(oc get openstackcontrolplane -n $(NAMESPACE) -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown"); \
		message=$$(oc get openstackcontrolplane -n $(NAMESPACE) -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].message}' 2>/dev/null || echo "Waiting..."); \
		if [ "$$status" = "True" ]; then \
			echo "✅ OpenStackControlPlane is Ready: $$message"; \
			break; \
		fi; \
		echo "[$$elapsed/$$timeout] Status: $$status - $$message"; \
		sleep 10; \
		elapsed=$$((elapsed + 10)); \
	done; \
	if [ $$elapsed -ge $$timeout ]; then \
		echo "❌ Timeout waiting for OpenStackControlPlane to be ready"; \
		exit 1; \
	fi

.PHONY: dataplane
dataplane: export KIND=OpenStackDataPlaneNodeSet
dataplane: export EDPM_ANSIBLE_SECRET=dataplane-ansible-ssh-private-key-secret
dataplane: export EDPM_NODE_IP=$(DATAPLANE_COMPUTE_IP)
dataplane: export EDPM_DEPLOY_DIR=$(OUT)/$(NAMESPACE)/dataplane/cr
dataplane: export EDPM_SERVER_ROLE=compute
dataplane: export EDPM_EXTRA_NOVA_CONFIG_FILE=$(OUT)/$(NAMESPACE)/dataplane/cr/25-nova-extra.conf
dataplane: check-install-yamls check-edpm-config ## Deploy data plane compute and wait
	@echo "=========================================="
	@echo "Deploying Data Plane Compute"
	@echo "Namespace: $(NAMESPACE)"
	@echo "Compute Node: $(DATAPLANE_COMPUTE_IP)"
	@echo "=========================================="
	@# Network IPs come from NetConfig (created during controlplane deployment)
	@# The dataplane.yaml uses Jinja2 templates that reference NetConfig values
	@cd $(INSTALL_YAMLS_DIR) && $(MAKE) edpm_deploy_prep
	@cd $(INSTALL_YAMLS_DIR) && $(MAKE) edpm_deploy
	@cd $(INSTALL_YAMLS_DIR) && $(MAKE) edpm_wait_deploy
	@echo ""
	@echo "=========================================="
	@echo "Running Nova Host Discovery"
	@echo "=========================================="
	@echo "Discovering compute hosts and mapping them to cells..."
	@oc -n $(NAMESPACE) exec nova-cell0-conductor-0 -- nova-manage cell_v2 discover_hosts --verbose || echo "⚠️  Host discovery failed - run manually if needed"
	@echo ""
	@echo "✅ Data plane deployment complete!"
	@echo "Verify hypervisors with: oc -n $(NAMESPACE) rsh openstackclient openstack hypervisor list"

.PHONY: clean-dataplane
clean-dataplane: ## Clean/delete the dataplane resources
	@echo "=========================================="
	@echo "Cleaning Data Plane Resources"
	@echo "Namespace: $(NAMESPACE)"
	@echo "=========================================="
	@echo "Deleting OpenStackDataPlaneDeployment resources..."
	@oc delete openstackdataplanedeployment --all -n $(NAMESPACE) --ignore-not-found=true
	@echo "Deleting OpenStackDataPlaneNodeSet resources..."
	@oc delete openstackdataplanenodeset --all -n $(NAMESPACE) --ignore-not-found=true
	@echo "Dataplane cleanup complete!"

##############################################################################
# VERIFICATION TARGETS
##############################################################################

.PHONY: verify-nncp
verify-nncp: ## Verify NNCP configuration and IP addresses
	@echo "=========================================="
	@echo "Verifying NNCP Configuration"
	@echo "=========================================="
	@echo ""
	@echo "NNCP Resources:"
	@oc get nncp
	@echo ""
	@echo "=========================================="
	@echo "IP Addresses on CRC Node"
	@echo "=========================================="
	@echo ""
	@echo "VLAN 20 (InternalAPI - $(NNCP_INTERFACE).20):"
	@oc -n default debug node/crc -- chroot /host ip addr show $(NNCP_INTERFACE).20 2>/dev/null | grep "inet " || echo "  Failed to get IPs"
	@echo ""
	@echo "VLAN 21 (Storage - $(NNCP_INTERFACE).21):"
	@oc -n default debug node/crc -- chroot /host ip addr show $(NNCP_INTERFACE).21 2>/dev/null | grep "inet " || echo "  Failed to get IPs"
	@echo ""
	@echo "VLAN 22 (Tenant - $(NNCP_INTERFACE).22):"
	@oc -n default debug node/crc -- chroot /host ip addr show $(NNCP_INTERFACE).22 2>/dev/null | grep "inet " || echo "  Failed to get IPs"
	@echo ""
	@echo "VLAN 23 (StorageMgmt - $(NNCP_INTERFACE).23):"
	@oc -n default debug node/crc -- chroot /host ip addr show $(NNCP_INTERFACE).23 2>/dev/null | grep "inet " || echo "  Failed to get IPs"
	@echo ""
	@echo "VLAN 25 (Designate - $(NNCP_INTERFACE).25):"
	@oc -n default debug node/crc -- chroot /host ip addr show $(NNCP_INTERFACE).25 2>/dev/null | grep "inet " || echo "  Failed to get IPs"
	@echo ""
	@echo "VLAN 26 (DesignateExt - $(NNCP_INTERFACE).26):"
	@oc -n default debug node/crc -- chroot /host ip addr show $(NNCP_INTERFACE).26 2>/dev/null | grep "inet " || echo "  Failed to get IPs"
	@echo ""
	@echo "=========================================="
	@echo "Summary: All VLAN interfaces checked"
	@echo "=========================================="

.PHONY: verify
verify: check-namespace ## Verify instance deployment (requires config sourced)
	@echo "=========================================="
	@echo "Verifying RHOSO Instance: $(NAMESPACE)"
	@echo "=========================================="
	@echo ""
	@echo "Namespace:"
	@oc get namespace $(NAMESPACE)
	@echo ""
	@echo "OpenStackControlPlane:"
	@oc get openstackcontrolplane -n $(NAMESPACE)
	@echo ""
	@echo "MetalLB Pools:"
	@oc get ipaddresspool -n metallb-system | grep $(NAMESPACE) || echo "No pools found for $(NAMESPACE)"
	@echo ""
	@echo "LoadBalancer Services:"
	@oc get svc -n $(NAMESPACE) -o wide | grep -E "LoadBalancer|NAME" || echo "No LoadBalancer services found"

##############################################################################
# CLEANUP TARGETS
##############################################################################

.PHONY: clean
clean: check-namespace ## Remove instance (requires config sourced)
	@echo "=========================================="
	@echo "Cleaning RHOSO Instance: $(NAMESPACE)"
	@echo "=========================================="
	@echo "Deleting namespace..."
	@oc delete namespace $(NAMESPACE) --ignore-not-found=true
	@echo ""
	@echo "Deleting MetalLB IPAddressPools..."
	@oc delete ipaddresspool -n metallb-system $(NAMESPACE)-ctlplane --ignore-not-found=true
	@oc delete ipaddresspool -n metallb-system $(NAMESPACE)-internalapi --ignore-not-found=true
	@oc delete ipaddresspool -n metallb-system $(NAMESPACE)-storage --ignore-not-found=true
	@oc delete ipaddresspool -n metallb-system $(NAMESPACE)-tenant --ignore-not-found=true
	@oc delete ipaddresspool -n metallb-system $(NAMESPACE)-designateext --ignore-not-found=true
	@echo ""
	@echo "Deleting MetalLB L2Advertisements..."
	@oc delete l2advertisement -n metallb-system $(NAMESPACE)-ctlplane --ignore-not-found=true
	@oc delete l2advertisement -n metallb-system $(NAMESPACE)-internalapi --ignore-not-found=true
	@oc delete l2advertisement -n metallb-system $(NAMESPACE)-storage --ignore-not-found=true
	@oc delete l2advertisement -n metallb-system $(NAMESPACE)-tenant --ignore-not-found=true
	@oc delete l2advertisement -n metallb-system $(NAMESPACE)-designateext --ignore-not-found=true
	@echo ""
	@echo "✅ Cleanup complete for $(NAMESPACE)"

.PHONY: clean-infrastructure
clean-infrastructure: ## Remove shared infrastructure operators (NMState, MetalLB, OpenStack)
	@echo "=========================================="
	@echo "Cleaning Shared Infrastructure"
	@echo "WARNING: This will remove NMState, MetalLB, and OpenStack operators!"
	@echo "=========================================="
	@echo "Deleting NMState operator..."
	@oc delete nmstate nmstate -n openshift-nmstate --ignore-not-found=true
	@oc delete subscription kubernetes-nmstate-operator -n openshift-nmstate --ignore-not-found=true
	@oc delete csv -n openshift-nmstate -l operators.coreos.com/kubernetes-nmstate-operator.openshift-nmstate --ignore-not-found=true
	@oc delete operatorgroup -n openshift-nmstate --all --ignore-not-found=true
	@oc delete namespace openshift-nmstate --ignore-not-found=true
	@echo ""
	@echo "Deleting MetalLB operator..."
	@oc delete metallb metallb -n metallb-system --ignore-not-found=true
	@oc delete subscription metallb-operator-sub -n metallb-system --ignore-not-found=true
	@oc delete csv -n metallb-system -l operators.coreos.com/metallb-operator.metallb-system --ignore-not-found=true
	@oc delete operatorgroup -n metallb-system --all --ignore-not-found=true
	@oc delete namespace metallb-system --ignore-not-found=true
	@echo ""
	@echo "Deleting OpenStack operators..."
	@oc delete namespace openstack-operators --ignore-not-found=true
	@oc delete namespace cert-manager --ignore-not-found=true
	@echo ""
	@echo "✅ Infrastructure cleanup complete"

.PHONY: clean-all
clean-all: ## Remove all instances and shared infrastructure
	@echo "=========================================="
	@echo "Cleaning All RHOSO Instances and Infrastructure"
	@echo "WARNING: This will remove all OpenStack operators!"
	@echo "Press Ctrl+C to cancel, Enter to continue..."
	@read confirm
	@echo ""
	@echo "Deleting all namespaces..."
	@for ns in $$(oc get namespaces -o name | grep -E 'rhoso|openstack'); do \
		echo "Deleting $$ns..."; \
		oc delete $$ns --ignore-not-found=true; \
	done
	@$(MAKE) clean-infrastructure
