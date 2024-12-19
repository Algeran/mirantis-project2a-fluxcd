##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk command is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

.EXPORT_ALL_VARIABLES:

##@ Binaries

# locataion to install binaries to
LOCALBIN ?= $(shell pwd)/bin
$(LOCALBIN):
	mkdir -p $(LOCALBIN)

KIND ?= PATH=$(LOCALBIN):$(PATH) kind
KIND_VERSION ?= 0.25.0

FLUX ?= PATH=$(LOCALBIN):$(PATH) flux
FLUX_VERSION ?= 2.4.0

HELM ?= PATH=$(LOCALBIN):$(PATH) helm
HELM_VERSION ?= v3.15.1

KUBECTL ?= PATH=$(LOCALBIN):$(PATH) kubectl

KUBESEAL ?= PATH=$(LOCALBIN):$(PATH) kubeseal
KUBESEAL_VERSION ?= 0.27.3

YQ ?= PATH=$(LOCALBIN):$(PATH) yq
YQ_VERSION ?= v4.44.6

OS=$(shell uname | tr A-Z a-z)
ifeq ($(shell uname -m),x86_64)
	ARCH=amd64
else
	ARCH=arm64
endif

.check-binary-%:
	@(which "$(binary)" $ > /dev/null || test -f $(LOCALBIN)/$(binary)) \
		|| (echo "Can't find the $(binary) in path, installing it locally" && make $(LOCALBIN)/$(binary))

.check-binary-docker:
	@if ! which docker $ > /dev/null; then \
		if [ "$(OS)" = "linux" ]; then \
			curl -sLO https://download.docker.com/linux/static/stable/$(shell uname -m)/docker-$(DOCKER_VERSION).tgz;\
			tar xzvf docker-$(DOCKER_VERSION).tgz; \
			sudo cp docker/* /usr/bin/ ; \
			echo "Starting docker daemon..." ; \
			sudo dockerd > /dev/null 2>&1 & sudo groupadd docker ; \
			sudo usermod -aG docker $(shell whoami) ; \
			newgrp docker ; \
			echo "Docker engine installed and started"; \
		else \
			echo "Please install docker before proceeding. If your work on machine with MacOS, check this installation guide: https://docs.docker.com/desktop/setup/install/mac-install/" && exit 1; \
		fi; \
	fi;

# installs binary locally
$(LOCALBIN)/%: $(LOCALBIN)
	@curl -sLo $(LOCALBIN)/$(binary) $(url);\
		chmod +x $(LOCALBIN)/$(binary);

%kind: binary = kind
%kind: url = "https://kind.sigs.k8s.io/dl/v$(KIND_VERSION)/kind-$(OS)-$(ARCH)"
%kubectl: binary = kubectl
%kubectl: url = "https://dl.k8s.io/release/$(shell curl -L -s https://dl.k8s.io/release/stable.txt)/bin/$(OS)/$(ARCH)/kubectl"
%flux: binary = flux
%helm: binary = helm
%kubeseal: binary = kubeseal
%yq: binary = yq
%yq: url = "https://github.com/mikefarah/yq/releases/download/$(YQ_VERSION)/yq_$(OS)_$(ARCH)"

.PHONY: kind
kind: $(LOCALBIN)/kind ## Install kind binary locally if necessary

.PHONY: kubectl
kubectl: $(LOCALBIN)/kubectl ## Install kubectl binary locally if necessary

.PHONY: helm
helm: $(LOCALBIN)/helm ## Install helm binary locally if necessary
HELM_INSTALL_SCRIPT ?= "https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3"
$(LOCALBIN)/helm: | $(LOCALBIN)
	rm -f $(LOCALBIN)/helm-*
	curl -s --fail $(HELM_INSTALL_SCRIPT) | USE_SUDO=false HELM_INSTALL_DIR=$(LOCALBIN) DESIRED_VERSION=$(HELM_VERSION) BINARY_NAME=helm PATH="$(LOCALBIN):$(PATH)" bash

.PHONY: flux
flux: $(LOCALBIN)/flux ## Install flux binary locally if necessary
$(LOCALBIN)/flux: | $(LOCALBIN)
	curl -sLO "https://github.com/fluxcd/flux2/releases/download/v$(FLUX_VERSION)/flux_$(FLUX_VERSION)_$(OS)_$(ARCH).tar.gz"
	@tar -xvzf flux_$(FLUX_VERSION)_$(OS)_$(ARCH).tar.gz;\
		chmod +x flux;\
		mv flux $(LOCALBIN)/flux;\
		rm -rf flux_$(FLUX_VERSION)_$(OS)_$(ARCH).tar.gz;

.PHONY: kubeseal
kubeseal: $(LOCALBIN)/kubeseal
$(LOCALBIN)/kubeseal: | $(LOCALBIN)
	@mkdir -p temp; \
		cd temp; \
		curl -sLO "https://github.com/bitnami-labs/sealed-secrets/releases/download/v$(KUBESEAL_VERSION)/kubeseal-$(KUBESEAL_VERSION)-$(OS)-$(ARCH).tar.gz"; \
		tar -xvzf kubeseal-$(KUBESEAL_VERSION)-$(OS)-$(ARCH).tar.gz; \
		chmod +x kubeseal; \
		cd ..; \
		mv temp/kubeseal $(LOCALBIN)/; \
		rm -rf temp


##@ General setup

# Management cluster deployment

KIND_CLUSTER_NAME?=hmc-management-local
KIND_CLUSTER_CONFIG_PATH ?= $(LOCALBIN)/kind-cluster.yaml

$(KIND_CLUSTER_CONFIG_PATH): $(LOCALBIN)
	@cat setup/kind-cluster.yaml | envsubst > $(LOCALBIN)/kind-cluster.yaml

.PHONY: bootstrap-kind-cluster
bootstrap-kind-cluster: .check-binary-docker .check-binary-kind .check-binary-kubectl $(KIND_CLUSTER_CONFIG_PATH) ## Provision local kind cluster
	@if $(KIND) get clusters | grep -q $(KIND_CLUSTER_NAME); then\
		echo "$(KIND_CLUSTER_NAME) kind cluster already installed";\
	else\
		$(KIND) create cluster --name=$(KIND_CLUSTER_NAME) --config=$(KIND_CLUSTER_CONFIG_PATH); \
	fi
	@$(KUBECTL) config use-context kind-$(KIND_CLUSTER_NAME)

# Flux CD deployment
GITHUB_TOKEN ?= 
GITHUB_USERNAME ?= 
GITHUB_REPO_NAME ?= 

.check-variable-%:
	@if [ "$($(var_name))" = "" ]; then\
		echo "Please define the $(var_description) with the $(var_name) variable";\
		exit 1;\
	fi

.%-github-pat: var_name = GITHUB_TOKEN
.%-github-pat: var_description = Github PAT token
.%-github-username: var_name = GITHUB_USERNAME
.%-github-username: var_description = Github username
.%-github-repo: var_name = GITHUB_REPO_NAME
.%-github-repo: var_description = Github repository name

.PHONY: bootstrap-flux
bootstrap-flux: .check-binary-flux .check-variable-github-pat .check-variable-github-username .check-variable-github-repo ## Bootstrap flux on the management cluster and store configuration to the specified Github repo. Make sure than you are in the right kubernetes context
	$(FLUX) bootstrap github \
		--token-auth \
		--owner=$(GITHUB_USERNAME) \
		--repository=$(GITHUB_REPO_NAME) \
		--branch=main \
		--path=flux/management \
		--personal

# 2A Platform deployment
HMC_VERSION ?= 0.0.5
HMC_NAMESPACE ?= hmc-system
FLUX_GIT_REPO_NAME = hmc-fluxcd-monorepo

# generates manifest from template
# $1 - template name
# $2 - directory in the gitops repo where the manifest should be placed
define generate-manifest
	@dir_path=$(2) && \
		template_path=$${dir_path#"$(LOCAL_GITOPS_REPO_PATH)/"} && \
		cat templates/$$template_path/$(1) | envsubst > $(2)/$(1)
endef

LOCAL_GITOPS_REPO_PATH ?= ../$(GITHUB_REPO_NAME)
$(LOCAL_GITOPS_REPO_PATH):
	@mkdir -p $(LOCAL_GITOPS_REPO_PATH)

$(LOCAL_GITOPS_REPO_PATH)/%:
	@mkdir -p $(dir $@)
	$(call generate-manifest,$(notdir $@),$(dir $@))

# applies kubectl manifests
# $1 - manifest path
define kubectl-apply
	@$(KUBECTL) apply -f $(1)
endef

# commit and push changes if required
# $1 - git repo path
# $2 - commit message
define git-commit-and-push
	@cd $(1);\
		git add . && git diff --quiet && git diff --cached --quiet \
		|| ( \
			git commit -m $(2) \
			&& git push origin main \
			);
endef

.PHONY: .fetch-repo
.fetch-repo: $(LOCAL_GITOPS_REPO_PATH) .check-variable-github-pat .check-variable-github-username .check-variable-github-repo
	@cd $(LOCAL_GITOPS_REPO_PATH); \
		git init; \
		git config remote.origin.url >&- || git remote add origin https://$(GITHUB_TOKEN)@github.com/$(GITHUB_USERNAME)/$(GITHUB_REPO_NAME).git; \
		git pull origin main; \
		git reset; \
		git checkout . ; \
		git clean -fdx

.PHONY: .generate-hmc-system-manifests
.generate-hmc-system-manifests: .fetch-repo $(LOCAL_GITOPS_REPO_PATH)/flux/management/hmc-system.yaml $(LOCAL_GITOPS_REPO_PATH)/management/hmc-system/hmc-operator.yaml $(LOCAL_GITOPS_REPO_PATH)/management/hmc-system/hmc-flux-networkpolicy.yaml

.PHONY: bootstrap-hmc-operator
bootstrap-hmc-operator: .fetch-repo .generate-hmc-system-manifests ## Generate hmc operator templates and deploy
	@$(call git-commit-and-push,$(LOCAL_GITOPS_REPO_PATH),"Added hmc system repository and hmc operator configuration")

# Local OCI Helm registry deployment
HELM_REGISTRY_INTERNAL_PORT ?= 5000
HELM_REGISTRY_EXTERNAL_PORT ?= 30500
HELM_REGISTRY_EXTERNAL_ADDRESS = oci://127.0.0.1:$(HELM_REGISTRY_EXTERNAL_PORT)/helm-charts

.PHONY: setup-helmrepo
setup-helmrepo: .fetch-repo
setup-helmrepo: $(LOCAL_GITOPS_REPO_PATH)/flux/management/helm-repository.yaml
setup-helmrepo: $(LOCAL_GITOPS_REPO_PATH)/management/helm-repository/helm-repository.yaml
setup-helmrepo: ## Deploy local helm repository and register it in 2A
	@$(call git-commit-and-push,$(LOCAL_GITOPS_REPO_PATH),"Added local Helm OCI repository configuration")
	@make helm-push-charts

HELM_CHARTS_DIR ?= $(shell pwd)/charts
HELM_CHARTS_PACKAGE_DIR ?= $(LOCALBIN)/charts
$(HELM_CHARTS_PACKAGE_DIR): $(LOCALBIN)
	mkdir -p $(HELM_CHARTS_PACKAGE_DIR)

.lint-chart-%: .check-binary-helm
	@$(HELM) dependency update $(CHART_GROUP_DIR)/$*
	@$(HELM) lint --strict $(CHART_GROUP_DIR)/$*

.package-chart-%: .check-binary-helm .lint-chart-% $(HELM_CHARTS_PACKAGE_DIR)
	@$(HELM) package --destination $(HELM_CHARTS_PACKAGE_DIR) $(CHART_GROUP_DIR)/$*

.package-charts-group-%:
	@if [ "$(sort $(dir $(wildcard $(HELM_CHARTS_DIR)/$*/*/*)))" != "" ]; then \
		make CHART_GROUP_DIR=$(HELM_CHARTS_DIR)/$* $(patsubst $(HELM_CHARTS_DIR)/$*/%/,.package-chart-%,$(sort $(dir $(wildcard $(HELM_CHARTS_DIR)/$*/*/*)))); \
	fi

.PHONY: helm-package-charts
helm-package-charts: ## Package Helm charts
	@make $(patsubst $(HELM_CHARTS_DIR)/%,.package-charts-group-%,$(wildcard $(HELM_CHARTS_DIR)/*))

.PHONY: helm-push-charts
helm-push-charts: helm-package-charts
helm-push-charts: ## Package and push Helm charts to the local Helm repository
	@while true; do\
		if $(KUBECTL) -n $(HMC_NAMESPACE) get deploy helm-registry; then \
			if [[ $$($(KUBECTL) -n $(HMC_NAMESPACE) get deploy helm-registry -o jsonpath={.status.readyReplicas}) > 0 ]]; then \
				break; \
			fi; \
		fi; \
		echo "Waiting when the helm registry be ready..."; \
		sleep 3; \
	done;
	@for chart in $(HELM_CHARTS_PACKAGE_DIR)/*.tgz; do \
		$(HELM) push "$$chart" $(HELM_REGISTRY_EXTERNAL_ADDRESS); \
	done

##@ Infra setup

KUBESEAL_DIR ?= $(shell pwd)/.kubeseal
$(KUBESEAL_DIR):
	@mkdir -p $(KUBESEAL_DIR)

KUBESEAL_CERTIFICATE = $(shell pwd)/.kubeseal/pub-sealed-secrets.pem
$(KUBESEAL_CERTIFICATE): $(KUBESEAL_DIR)
	$(KUBESEAL) --fetch-cert \
		--controller-name=sealed-secrets-controller \
		--controller-namespace=$(HMC_NAMESPACE) \
		> $(KUBESEAL_CERTIFICATE)

.retrieve-kubeseal-certificate: .check-binary-kubeseal $(KUBESEAL_DIR)
	@while true; do\
		if $(KUBECTL) -n $(HMC_NAMESPACE) get deploy sealed-secrets-controller; then \
			if [[ $$($(KUBECTL) -n $(HMC_NAMESPACE) get deploy sealed-secrets-controller -o jsonpath={.status.readyReplicas}) > 0 ]]; then \
				break; \
			fi; \
		fi; \
		echo "Waiting when the kubeseal controller be ready..."; \
		sleep 3; \
	done;
	make $(KUBESEAL_CERTIFICATE)

install-kubeseal: .fetch-repo $(LOCAL_GITOPS_REPO_PATH)/flux/management/sealed-secrets.yaml $(LOCAL_GITOPS_REPO_PATH)/management/sealed-secrets/sealed-secrets.yaml ## Generate kubeseal manifests and deploy
	@$(call git-commit-and-push,$(LOCAL_GITOPS_REPO_PATH),"Added kubeseal configuration")
	@make .retrieve-kubeseal-certificate;

GITOPS_CREDENTIALS_DIR = $(LOCAL_GITOPS_REPO_PATH)/credentials
$(GITOPS_CREDENTIALS_DIR):
	@mkdir -p $(GITOPS_CREDENTIALS_DIR)

.PHONY: .setup-credential-providers-in-flux
.setup-credential-providers-in-flux: .fetch-repo $(GITOPS_CREDENTIALS_DIR) $(LOCAL_GITOPS_REPO_PATH)/flux/management/provider-credentials.yaml
	@touch $(GITOPS_CREDENTIALS_DIR)/.gitkeep
	@$(call git-commit-and-push,$(LOCAL_GITOPS_REPO_PATH),"Added proviver credentials configuration")

# AWS credentials

.%-aws-access-key: var_name = AWS_ACCESS_KEY_ID
.%-aws-access-key: var_description = AWS access key ID
.%-aws-secret-access-key: var_name = AWS_SECRET_ACCESS_KEY
.%-aws-secret-access-key: var_description = AWS secret access key

AWS_CREDENTIAL_NAME = aws-credential
AWS_CREDENTIALS_SECRET_NAME = aws-cluster-identity-secret
setup-aws-creds: $(KUBESEAL_CERTIFICATE) .check-variable-aws-access-key .check-variable-aws-secret-access-key .setup-credential-providers-in-flux $(GITOPS_CREDENTIALS_DIR)/aws/credentials.yaml ## Generate and deploy AWS credentials
	@$(KUBECTL) -n $(HMC_NAMESPACE) create secret generic $(AWS_CREDENTIALS_SECRET_NAME) \
		--from-literal=AccessKeyID=$(AWS_ACCESS_KEY_ID) \
		--from-literal=SecretAccessKey=$(AWS_SECRET_ACCESS_KEY) \
		--dry-run=client -o yaml \
		| $(KUBESEAL) --format yaml --cert=$(KUBESEAL_CERTIFICATE) > $(GITOPS_CREDENTIALS_DIR)/aws/$(AWS_CREDENTIALS_SECRET_NAME).yaml
	@$(call git-commit-and-push,$(LOCAL_GITOPS_REPO_PATH),"Added AWS credentials")

# Azure

.%-azure-sp-password: var_name = AZURE_SP_PASSWORD
.%-azure-sp-password: var_description = Azure Service Principal password
.%-azure-sp-app-id: var_name = AZURE_SP_APP_ID
.%-azure-sp-app-id: var_description = Azure Service Principal App ID
.%-azure-sp-tenant-id: var_name = AZURE_SP_TENANT_ID
.%-azure-sp-tenant-id: var_description = Azure Service Principal Tenant ID

AZURE_CREDENTIAL_NAME = azure-credential
AZURE_CREDENTIALS_SECRET_NAME = azure-cluster-identity-secret
setup-azure-creds: $(KUBESEAL_CERTIFICATE) .check-variable-azure-sp-password .check-variable-azure-sp-app-id .check-variable-azure-sp-tenant-id  .setup-credential-providers-in-flux $(GITOPS_CREDENTIALS_DIR)/azure/credentials.yaml ## Generate and deploy Azure credentials
	@$(KUBECTL) -n $(HMC_NAMESPACE) create secret generic $(AZURE_CREDENTIALS_SECRET_NAME) \
		--from-literal=clientSecret=$(AZURE_SP_PASSWORD) \
		--dry-run=client -o yaml \
		| $(KUBESEAL) --format yaml --cert=$(KUBESEAL_CERTIFICATE) > $(GITOPS_CREDENTIALS_DIR)/azure/$(AZURE_CREDENTIALS_SECRET_NAME).yaml
	@$(call git-commit-and-push,$(LOCAL_GITOPS_REPO_PATH),"Added Azure credentials")

##@ Demos

KUBECONFIGS_DIR = $(shell pwd)/kubeconfigs
$(KUBECONFIGS_DIR):
	@mkdir -p $(KUBECONFIGS_DIR)

GITOPS_MANAGED_CLUSTERS_DIR = $(LOCAL_GITOPS_REPO_PATH)/clusters
$(GITOPS_MANAGED_CLUSTERS_DIR):
	@mkdir -p $(GITOPS_MANAGED_CLUSTERS_DIR)

.PHONY: .setup-managed-clusters-in-flux
.setup-managed-clusters-in-flux: .fetch-repo $(GITOPS_MANAGED_CLUSTERS_DIR) $(LOCAL_GITOPS_REPO_PATH)/flux/management/managed-clusters.yaml
	@touch $(GITOPS_MANAGED_CLUSTERS_DIR)/.gitkeep
	@$(call git-commit-and-push,$(LOCAL_GITOPS_REPO_PATH),"Added managed clusters configuration")

GITOPS_GLOBAL_SERVICS_DIR = $(LOCAL_GITOPS_REPO_PATH)/services
$(GITOPS_GLOBAL_SERVICS_DIR):
	@mkdir -p $(GITOPS_GLOBAL_SERVICS_DIR)

.PHONY: .setup-services-in-flux
.setup-services-in-flux: .fetch-repo $(GITOPS_GLOBAL_SERVICS_DIR) $(LOCAL_GITOPS_REPO_PATH)/flux/management/global-services.yaml
	@touch $(GITOPS_GLOBAL_SERVICS_DIR)/.gitkeep
	@$(call git-commit-and-push,$(LOCAL_GITOPS_REPO_PATH),"Added global beach-head services configuration")

.%-username: var_name = USERNAME
.%-username: var_description = username to create unique cloud resources

# Demo 1
CLUSTER_TEMPLATE_AWS_STANDALONE_BUILT_IN ?= aws-standalone-cp-0-0-4
.PHONY: deploy-builtin-aws-standalone
deploy-builtin-aws-standalone: .check-variable-username .check-binary-yq .setup-managed-clusters-in-flux
deploy-builtin-aws-standalone: $(GITOPS_MANAGED_CLUSTERS_DIR)/aws/managed-builtin-standalone-aws.yaml
deploy-builtin-aws-standalone: $(GITOPS_MANAGED_CLUSTERS_DIR)/aws/patches/builtin-standalone-0.0.4.yaml
deploy-builtin-aws-standalone: $(GITOPS_MANAGED_CLUSTERS_DIR)/kustomization.yaml
deploy-builtin-aws-standalone: $(GITOPS_MANAGED_CLUSTERS_DIR)/aws/kustomization.yaml
deploy-builtin-aws-standalone: ## Demo 1: deploy AWS standalone cluster
	@$(YQ) -i 'with(.patches; select(all_c(.target.name != "managed-builtin-standalone-aws")) | . += {"target" : {"name": "managed-builtin-standalone-aws", "kind": "ManagedCluster"}})' $(GITOPS_MANAGED_CLUSTERS_DIR)/aws/kustomization.yaml
	@$(YQ) -i ' \
			.resources |= ((. // []) + "managed-builtin-standalone-aws.yaml" | unique) | \
			(.patches[] | select(.target.name == "managed-builtin-standalone-aws") | .path) = "patches/builtin-standalone-0.0.4.yaml" \
		' $(GITOPS_MANAGED_CLUSTERS_DIR)/aws/kustomization.yaml
	@$(YQ) -i '.resources |= ((. // []) + "aws" | unique)' $(GITOPS_MANAGED_CLUSTERS_DIR)/kustomization.yaml
	@$(call git-commit-and-push,$(LOCAL_GITOPS_REPO_PATH),"Added managed built-in AWS standalone cluster 0.0.4")

.PHONY: watch-builtin-aws-standalone
watch-builtin-aws-standalone: .check-binary-kubectl
watch-builtin-aws-standalone: ## Demo 1: monitor the AWS standalone cluster status
	@$(KUBECTL) get -n $(HMC_NAMESPACE) managedcluster managed-builtin-standalone-aws-$(USERNAME) --watch

.PHONY: get-kubeconfig-builtin-aws-standalone
get-kubeconfig-builtin-aws-standalone: .check-binary-kubectl
get-kubeconfig-builtin-aws-standalone: $(KUBECONFIGS_DIR) ## Demo 1: get kubeconfig for the AWS standalone cluster
	@$(KUBECTL) -n $(HMC_NAMESPACE) get secret managed-builtin-standalone-aws-$(USERNAME)-kubeconfig -o jsonpath='{.data.value}' | base64 -d > $(KUBECONFIGS_DIR)/managed-builtin-standalone-aws-$(USERNAME).kubeconfig

# Demo 2
.PHONY: deploy-builtin-aws-standalone-ingress
deploy-builtin-aws-standalone-ingress: .check-variable-username .check-binary-yq
deploy-builtin-aws-standalone-ingress: $(GITOPS_MANAGED_CLUSTERS_DIR)/services/ingress/nginx-4-11-0.yaml
deploy-builtin-aws-standalone-ingress: ## Demo 2: patch AWS standalone cluster with ingress controller
	@$(YQ) -i 'with(.patches; select(all_c(.target.labelSelector != "hmc-service/ingress=nginx-4-11-0")) | \
		. += {"target": {"kind" : "ManagedCluster", "labelSelector": "hmc-service/ingress=nginx-4-11-0"}, "path": "services/ingress/nginx-4-11-0.yaml"})' \
		$(GITOPS_MANAGED_CLUSTERS_DIR)/kustomization.yaml
	@$(YQ) -i '.metadata.labels.hmc-service/ingress = "nginx-4-11-0"' $(GITOPS_MANAGED_CLUSTERS_DIR)/aws/managed-builtin-standalone-aws.yaml
	@$(call git-commit-and-push,$(LOCAL_GITOPS_REPO_PATH),"Installed ingress controller 4.11.0 on AWS standalone cluster 0.0.4")

# Demo 3
.%-azure-subscription-id: var_name = AZURE_SUBSCRIPTION_ID
.%-azure-subscription-id: var_description = Azure Subscription ID

CLUSTER_TEMPLATE_AZURE_STANDALONE_BUILT_IN ?= azure-standalone-cp-0-0-4
.PHONY: deploy-builtin-azure-standalone
deploy-builtin-azure-standalone: .check-variable-username .check-variable-azure-subscription-id .check-binary-yq .setup-managed-clusters-in-flux
deploy-builtin-azure-standalone: $(GITOPS_MANAGED_CLUSTERS_DIR)/azure/managed-builtin-standalone-azure.yaml
deploy-builtin-azure-standalone: $(GITOPS_MANAGED_CLUSTERS_DIR)/azure/patches/builtin-standalone-0.0.4.yaml
deploy-builtin-azure-standalone: $(GITOPS_MANAGED_CLUSTERS_DIR)/kustomization.yaml
deploy-builtin-azure-standalone: $(GITOPS_MANAGED_CLUSTERS_DIR)/azure/kustomization.yaml
deploy-builtin-azure-standalone: ## Demo 3: deploy Azure standalone cluster
	@$(YQ) -i 'with(.patches; select(all_c(.target.name != "managed-builtin-standalone-azure")) | . += {"target" : {"name": "managed-builtin-standalone-azure", "kind": "ManagedCluster"}})' $(GITOPS_MANAGED_CLUSTERS_DIR)/azure/kustomization.yaml
	@$(YQ) -i ' \
			.resources |= ((. // []) + "managed-builtin-standalone-azure.yaml" | unique) | \
			(.patches[] | select(.target.name == "managed-builtin-standalone-azure") | .path) = "patches/builtin-standalone-0.0.4.yaml" \
		' $(GITOPS_MANAGED_CLUSTERS_DIR)/azure/kustomization.yaml
	@$(YQ) -i '.resources |= ((. // []) + "azure" | unique)' $(GITOPS_MANAGED_CLUSTERS_DIR)/kustomization.yaml
	@$(call git-commit-and-push,$(LOCAL_GITOPS_REPO_PATH),"Added managed built-in Azure standalone cluster 0.0.4")

.PHONY: watch-builtin-azure-standalone
watch-builtin-azure-standalone: .check-binary-kubectl
watch-builtin-azure-standalone: ## Demo 3: monitor the Azure standalone cluster status
	@$(KUBECTL) get -n $(HMC_NAMESPACE) managedcluster managed-builtin-standalone-azure-$(USERNAME) --watch

.PHONY: get-kubeconfig-builtin-azure-standalone
get-kubeconfig-builtin-azure-standalone: .check-binary-kubectl $(KUBECONFIGS_DIR)
get-kubeconfig-builtin-azure-standalone: ## Demo 3: get kubeconfig for the Azure standalone cluster
	@$(KUBECTL) -n $(HMC_NAMESPACE) get secret managed-builtin-standalone-azure-$(USERNAME)-kubeconfig -o jsonpath='{.data.value}' | base64 -d > $(KUBECONFIGS_DIR)/managed-builtin-standalone-azure-$(USERNAME).kubeconfig

# Demo 4
.PHONY: deploy-global-kyverno
deploy-global-kyverno: .setup-services-in-flux
deploy-global-kyverno: $(GITOPS_GLOBAL_SERVICS_DIR)/policy-management/kyverno-3-2-6.yaml
deploy-global-kyverno:  ## Demo 4: deploy MultiClusterService
	@$(call git-commit-and-push,$(LOCAL_GITOPS_REPO_PATH),"Added global beach-head service Kyverno and deployed to AWS and Azure clusters")
	

##@ Cleanup

.PHONY: .flux-suspend
.flux-suspend:
	@if $(KIND) get clusters | grep -q $(KIND_CLUSTER_NAME); then \
		$(FLUX) suspend kustomization -n $(HMC_NAMESPACE) --all; \
	fi

.PHONY: .delete-managed-clusters
.delete-managed-clusters: .flux-suspend
	@if $(KIND) get clusters | grep -q $(KIND_CLUSTER_NAME); then \
		$(KUBECTL) -n $(HMC_NAMESPACE) delete managedcluster --all --wait=false; \
		while [[ $$($(KUBECTL) -n $(HMC_NAMESPACE) get managedcluster -o go-template='{{ len .items }}') > 0 ]]; do \
			echo "Waiting untill all managed clusters are deleted..."; \
			sleep 3; \
		done; \
	fi

.PHONY: delete-kind-cluster
.delete-kind-cluster: .delete-managed-clusters .check-binary-kind
	@if $(KIND) get clusters | grep -q $(KIND_CLUSTER_NAME); then\
		$(KIND) delete cluster --name=$(KIND_CLUSTER_NAME);\
	else\
		echo "Kind cluster with the name $(KIND_CLUSTER_NAME) is not detected";\
	fi

.PHONY: .cleanup-local
.cleanup-local:
	@rm -rf .kubeseal
	@rm -rf kubeconfigs
	@rm -rf $(KIND_CLUSTER_CONFIG_PATH)
	@rm -rf $(HELM_CHARTS_PACKAGE_DIR)

PHONY: cleanup
cleanup: .delete-kind-cluster .cleanup-local ## Delete managed clusters and cleanup local environment
