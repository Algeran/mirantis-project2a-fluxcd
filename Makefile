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

TERRAFORM ?= PATH=$(LOCALBIN):$(PATH) terraform
TERRAFORM_VERSION ?= 1.10.2

KUBESEAL ?= PATH=$(LOCALBIN):$(PATH) kubeseal
KUBESEAL_VERSION ?= 0.27.3

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
	@which docker $ > /dev/null || (echo "Please install docker before proceeding" && exit 1)

# installs binary locally
$(LOCALBIN)/%: $(LOCALBIN)
	@curl -sLo $(LOCALBIN)/$(binary) $(url);\
		chmod +x $(LOCALBIN)/$(binary);

%kind: binary = kind
%kind: url = "https://kind.sigs.k8s.io/dl/v$(KIND_VERSION)/kind-$(OS)-$(ARCH)"
%kubectl: binary = kubectl
%kubectl: url = "https://dl.k8s.io/release/$(shell curl -L -s https://dl.k8s.io/release/stable.txt)/bin/$(OS)/$(ARCH)/kubectl"
%flux: binary = flux
%terraform: binary = terraform
%kubeseal: binary = kubeseal


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

.PHONY: terraform
terraform: $(LOCALBIN)/terraform ## Install terraform binary locally if necessary
$(LOCALBIN)/terraform: | $(LOCALBIN)
	@mkdir -p temp;\
		cd temp;\
		curl -sLO "https://releases.hashicorp.com/terraform/$(TERRAFORM_VERSION)/terraform_$(TERRAFORM_VERSION)_$(OS)_$(ARCH).zip";\
		unzip terraform_$(TERRAFORM_VERSION)_$(OS)_$(ARCH).zip;\
		chmod +x terraform;\
		cd ..;\
		mv temp/terraform $(LOCALBIN)/terraform;\
		rm -rf temp

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

##@ Bootstrap/tear down kubernetes management cluster

KIND_CLUSTER_NAME?=hmc-management-local

.PHONY: bootstrap-kind-cluster
bootstrap-kind-cluster: .check-binary-docker .check-binary-kind .check-binary-kubectl ## Provision local kind cluster
	@if $(KIND) get clusters | grep -q $(KIND_CLUSTER_NAME); then\
		echo "$(KIND_CLUSTER_NAME) kind cluster already installed";\
	else\
		$(KIND) create cluster --name=$(KIND_CLUSTER_NAME);\
	fi
	$(KUBECTL) config use-context kind-$(KIND_CLUSTER_NAME)

K3S_CLUSTER_VERSION ?= v1.31.3+k3s1
K3S_ARGS ?=
K3S_PUBLIC_IP_LB ?=

.PHONY: .generate-ssh-keys
.generate-ssh-keys:
	@if ! test -f "terraform/aws/cluster-infra/.keys/ssh-mgmt"; then\
		mkdir -p terraform/aws/cluster-infra/.keys;\
		ssh-keygen -t rsa -b 2048 -f terraform/aws/cluster-infra/.keys/ssh-mgmt -q -N "";\
	fi

.PHONY: .provision-k3s-infra
.provision-k3s-infra: .check-binary-terraform .generate-ssh-keys
	cd terraform/aws/cluster-infra;\
		$(TERRAFORM) init;\
		$(TERRAFORM) apply -auto-approve

.PHONY: .management-cluster-ip-terraform
.management-cluster-ip-terraform:
MANAGEMENT_CLUSTER_INSTANCE_IP=$(shell $(TERRAFORM) -chdir=terraform/aws/cluster-infra/ output -json | jq -r .manager_vm_ip.value)
K3S_ARGS += --tls-san=$(MANAGEMENT_CLUSTER_INSTANCE_IP)

.PHONY: .management-cluster-ip-manual
.management-cluster-ip-manual:
ifdef K3S_PUBLIC_IP_LB
K3S_ARGS += --tls-san=$(K3S_PUBLIC_IP_LB)
endif

.PHONY: bootstrap-k3s-over-aws
bootstrap-k3s-over-aws: .provision-k3s-infra .management-cluster-ip-terraform ## Provision AWS infra and install k3s over it
	ssh -i terraform/aws/cluster-infra/.keys/ssh-mgmt ubuntu@$(MANAGEMENT_CLUSTER_INSTANCE_IP) \
		'export INSTALL_K3S_VERSION=$(K3S_CLUSTER_VERSION); curl -sfL https://get.k3s.io | sh -s - server \
		--cluster-init \
		--secrets-encryption \
		--node-name=manager-1 \
		--node-label=role=manager \
		$(K3S_ARGS); \
		sudo cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/kubeconfig.yaml; \
		sudo chown ubuntu:ubuntu /home/ubuntu/kubeconfig.yaml; \
		sed -i "s@server: https://127.0.0.1:6443@server: https://$(MANAGEMENT_CLUSTER_INSTANCE_IP):6443@g" /home/ubuntu/kubeconfig.yaml \
		'
	@scp -i terraform/aws/cluster-infra/.keys/ssh-mgmt ubuntu@$(MANAGEMENT_CLUSTER_INSTANCE_IP):/home/ubuntu/kubeconfig.yaml ./mgmt-kubeconfig.yaml
	@echo "\
	Get access to the management cluster with the command:\n\n\
	  export KUBECONFIG=$$(pwd)/mgmt-kubeconfig.yaml\n\
	  kubectl get no\
	"
	@echo "\
	To login on the remote machine with k3s cluster execute the following command:\n\n\
		ssh -i $$(pwd)/terraform/aws/cluster-infra/.keys/ssh-mgmt ubuntu@$(MANAGEMENT_CLUSTER_INSTANCE_IP)\n\
	"

.PHONY: bootstrap-k3s
bootstrap-k3s: .management-cluster-ip-manual ## (Linux only) Provision local k3s cluster
	curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="$(K3S_CLUSTER_VERSION)" sh -s - server \
		--cluster-init \
		--secrets-encryption \
		--node-name=manager-1 \
		--node-label=role=manager \
		$(K3S_ARGS)
	@echo "Copy the kubeconfig from /etc/rancher/k3s/k3s.yaml and change the kubernetes API address to the public load balancer IP if it was specified"

.PHONY: delete-kind-cluster
delete-kind-cluster: .check-binary-kind ## Tear down local kind cluster
	@if $(KIND) get clusters | grep -q $(KIND_CLUSTER_NAME); then\
		$(KIND) delete cluster --name=$(KIND_CLUSTER_NAME);\
	else\
		echo "Kind cluster with the name $(KIND_CLUSTER_NAME) is not detected";\
	fi

.PHONY: delete-k3s-over-aws
delete-k3s-over-aws: .check-binary-terraform ## Destroy AWS infra with the installed k3s cluster
	$(TERRAFORM) -chdir=terraform/aws/cluster-infra destroy -auto-approve
	rm -rf mgmt-kubeconfig.yaml
	rm -rf terraform/aws/cluster-infra/.keys

.PHONY: delete-k3s
delete-k3s: ## (Linux only) Tear down local k3s cluster
	/usr/local/bin/k3s-uninstall.sh

##@ Bootstrap flux on the management cluster

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


##@ Deploy Project 2A

HMC_VERSION ?= 0.0.5
HMC_NAMESPACE ?= hmc-system
FLUX_GIT_REPO_NAME = hmc-fluxcd-monorepo

# generates manifest from Makefile template
# $1 - Makefile template name (specified in define block)
# $2 - directory in the gitops repo where the manifest should be placed
# $3 - manifest name
define generate-template
	@echo "$$$(1)" > $(2)/$(3)
endef

LOCAL_GITOPS_REPO_PATH ?= ../$(GITHUB_REPO_NAME)
$(LOCAL_GITOPS_REPO_PATH):
	@mkdir -p $(LOCAL_GITOPS_REPO_PATH)

FLUX_MANAGEMENT_DIR = $(LOCAL_GITOPS_REPO_PATH)/flux/management
$(FLUX_MANAGEMENT_DIR):
	@mkdir -p $(FLUX_MANAGEMENT_DIR)

$(FLUX_MANAGEMENT_DIR)/%: $(FLUX_MANAGEMENT_DIR)
	$(call generate-template,$(template_name),$(FLUX_MANAGEMENT_DIR),$(notdir $@))

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

.fetch-repo: $(LOCAL_GITOPS_REPO_PATH) .check-variable-github-pat .check-variable-github-username .check-variable-github-repo
	@cd $(LOCAL_GITOPS_REPO_PATH);\
		git init;\
		git config remote.origin.url >&- || git remote add origin https://$(GITHUB_TOKEN)@github.com/$(GITHUB_USERNAME)/$(GITHUB_REPO_NAME).git;\
		git pull origin main;\

include templates/management/Makefile.2a-platform.mk
.PHONY: bootstrap-hmc-operator
bootstrap-hmc-operator: .fetch-repo .generate-hmc-system-manifests ## Generate hmc operator templates and deploy
	@$(call git-commit-and-push,$(LOCAL_GITOPS_REPO_PATH),"Added hmc system repository and hmc operator configuration")
	@make .kubectl-apply-hmc-system;


##@ Provider credentials

include templates/management/Makefile.kubeseal.mk
KUBESEAL_DIR ?= $(shell pwd)/.kubeseal
$(KUBESEAL_DIR):
	@mkdir -p $(KUBESEAL_DIR) = $(shell pwd)/.kubeseal/

KUBESEAL_CERTIFICATE = $(shell pwd)/.kubeseal/pub-sealed-secrets.pem
$(KUBESEAL_CERTIFICATE):
	@mkdir -p $(shell pwd)/.kubeseal/
	$(KUBESEAL) --fetch-cert \
		--controller-name=sealed-secrets-controller \
		--controller-namespace=$(HMC_NAMESPACE) \
		> $(KUBESEAL_CERTIFICATE)

.retrieve-kubeseal-certificate: .check-binary-kubeseal $(KUBESEAL_DIR)
	@while true; do\
		if $(KUBECTL) -n hmc-system get deploy sealed-secrets-controller; then \
			if [[ $$($(KUBECTL) -n hmc-system get deploy sealed-secrets-controller -o jsonpath={.status.readyReplicas}) > 0 ]]; then \
				break; \
			fi; \
		fi; \
		echo "Waiting when the kubeseal controller be ready..."; \
		sleep 3; \
	done;
	make $(KUBESEAL_CERTIFICATE)

install-kubeseal: .fetch-repo .generate-kubeseal-manifests ## Generate kubeseal manifests and deploy
	@$(call git-commit-and-push,$(LOCAL_GITOPS_REPO_PATH),"Added kubeseal configuration")
	@make .kubectl-apply-kubeseal;
	@make .retrieve-kubeseal-certificate;

include templates/credentials/Makefile.credentials.mk
.PHONY: .setup-credential-providers-in-flux
.setup-credential-providers-in-flux: .fetch-repo .generate-provider-credentials
	@$(call git-commit-and-push,$(LOCAL_GITOPS_REPO_PATH),"Added proviver credentials configuration")
	@make .kubectl-apply-provider-credentials

# AWS credentials

.%-aws-access-key: var_name = AWS_ACCESS_KEY_ID
.%-aws-access-key: var_description = AWS access key ID
.%-aws-secret-access-key: var_name = AWS_SECRET_ACCESS_KEY
.%-aws-secret-access-key: var_description = AWS secret access key

include templates/credentials/Makefile.aws.mk
setup-aws-creds: $(KUBESEAL_CERTIFICATE) .check-variable-aws-access-key .check-variable-aws-secret-access-key .setup-credential-providers-in-flux .generate-aws-credentials-manifests ## Generate and deploy AWS credentials
	@$(KUBECTL) -n $(HMC_NAMESPACE) create secret generic aws-cluster-identity-secret \
		--from-literal=AccessKeyID=$(AWS_ACCESS_KEY_ID) \
		--from-literal=SecretAccessKey=$(AWS_SECRET_ACCESS_KEY) \
		--dry-run=client -o yaml \
		| $(KUBESEAL) --format yaml --cert=$(KUBESEAL_CERTIFICATE) > $(GITOPS_AWS_CREDENTIALS_DIR)/aws-cluster-identity-secret.yaml
	@$(call git-commit-and-push,$(LOCAL_GITOPS_REPO_PATH),"Added AWS credentials")

# TODO: Add Azure and others

##@ Demos

KUBECONFIGS_DIR = $(shell pwd)/kubeconfigs
$(KUBECONFIGS_DIR):
	@mkdir -p $(KUBECONFIGS_DIR)

include templates/clusters/Makefile.clusters.mk
.PHONY: .setup-managed-clusters-in-flux
.setup-managed-clusters-in-flux: .fetch-repo .generate-managed-clusters-config
	@$(call git-commit-and-push,$(LOCAL_GITOPS_REPO_PATH),"Added managed clusters configuration")
	@make .kubectl-apply-managed-clusters-config

include templates/clusters/Makefile.aws.mk
.%-username: var_name = USERNAME
.%-username: var_description = username to create unique cloud resources

# Demo 1
.PHONY: deploy-aws-standalone-0-0-4
deploy-aws-standalone-0-0-4: .check-variable-username .setup-managed-clusters-in-flux .generate-aws-standalone-0-0-4-manifest ## Demo 1: deploy AWS standalone cluster
	@$(call git-commit-and-push,$(LOCAL_GITOPS_REPO_PATH),"Added managed AWS standalone cluster 0.0.4")

.PHONY: watch-aws-standalone-0-0-4
watch-aws-standalone-0-0-4: ## Demo 1: monitor the AWS standalone cluster status
	@$(KUBECTL) get -n $(HMC_NAMESPACE) managedcluster managed-standalone-aws-$(USERNAME) --watch

.PHONY: get-kubeconfig-aws-standalone-0-0-4
get-kubeconfig-aws-standalone-0-0-4: $(KUBECONFIGS_DIR) ## Demo 1: get kubeconfig for the AWS standalone cluster
	@$(KUBECTL) -n $(HMC_NAMESPACE) get secret managed-standalone-aws-$(USERNAME)-kubeconfig -o jsonpath='{.data.value}' | base64 -d > $(KUBECONFIGS_DIR)/managed-standalone-aws-$(USERNAME).kubeconfig

# Demo 2
.PHONY: deploy-aws-standalone-0-0-4-ingress
deploy-aws-standalone-0-0-4-ingress: .generate-aws-standalone-0-0-4-with-ingress ## Demo 2: patch AWS standalone cluster with ingress controller
	@$(call git-commit-and-push,$(LOCAL_GITOPS_REPO_PATH),"Installed ingress controller 4.11.0 on AWS standalone cluster 0.0.4")


