define PROVIDER_CREDENTIALS_FLUX
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: provider-credentials
  namespace: $(HMC_NAMESPACE)
spec:
  interval: 10m0s
  path: ./credentials
  prune: true
  sourceRef:
    kind: GitRepository
    name: $(FLUX_GIT_REPO_NAME)
    namespace: $(HMC_NAMESPACE)
endef
export PROVIDER_CREDENTIALS_FLUX

$(FLUX_MANAGEMENT_DIR)/provider-credentials.yaml: template_name = PROVIDER_CREDENTIALS_FLUX

GITOPS_CREDENTIALS_DIR = $(LOCAL_GITOPS_REPO_PATH)/credentials
$(GITOPS_CREDENTIALS_DIR):
	@mkdir -p $(GITOPS_CREDENTIALS_DIR)
	@touch $(GITOPS_CREDENTIALS_DIR)/.gitkeep

.PHONY: .generate-provider-credentials
.generate-provider-credentials: .fetch-repo $(GITOPS_CREDENTIALS_DIR) $(FLUX_MANAGEMENT_DIR)/provider-credentials.yaml

.PHONY: .kubectl-apply-provider-credentials
.kubectl-apply-provider-credentials:
	$(call kubectl-apply,$(FLUX_MANAGEMENT_DIR)/provider-credentials.yaml)