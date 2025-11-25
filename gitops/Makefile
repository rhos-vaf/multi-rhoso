# VA (Validated Architecture) Deployment Makefile
#
# This Makefile provides targets for deploying RHOSO instances using GitOps (ArgoCD).
#
# Usage:
#   make help              - Show available targets
#   make gitops            - Install OpenShift GitOps Operator
#   make cluster-wide-permissions - Configure ArgoCD with cluster-wide permissions

# Default target - show help
.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help message
	@echo "VA (Validated Architecture) GitOps Deployment Targets:"
	@echo ""
	@echo "OpenShift GitOps Installation:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-30s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Examples:"
	@echo "  make gitops                      - Install OpenShift GitOps Operator"
	@echo "  make cluster-wide-permissions    - Configure ArgoCD with cluster admin access"

.PHONY: gitops
gitops: ## Install OpenShift GitOps Operator
	@echo "=========================================="
	@echo "Installing OpenShift GitOps Operator"
	@echo "=========================================="
	@oc apply -f openshift-gitops-configs/gitops-operator-install.yaml
	@echo ""
	@echo "✅ OpenShift GitOps Operator installation initiated"
	@echo ""
	@echo "Verify installation with:"
	@echo "  oc get subscription -n openshift-gitops-operator"
	@echo "  oc get csv -n openshift-gitops-operator"
	@echo "  oc get pods -n openshift-gitops"


##@ CONFIGURE OPENSHIFT GITOPS
.PHONY: cluster-wide-permissions
cluster-wide-permissions: ## Grant cluster-wide permissions to openshift-gitops instance
	@echo "Configuring OpenShift GitOps with cluster-wide permissions"
	@oc apply -f openshift-gitops-configs/openshift-gitops-rbac.yaml
	@echo "Configuring OpenShift GitOps RBAC policy"
	@oc patch argocd openshift-gitops -n openshift-gitops --type=merge -p '{"spec":{"rbac":{"defaultPolicy":"role:readonly","policy":"g, system:cluster-admins, role:admin\ng, kubeadmin, role:admin\ng, system:authenticated, role:admin\n","scopes":"[groups]"}}}'
	@echo "OpenShift GitOps configured successfully with cluster-wide permissions and RBAC policy"