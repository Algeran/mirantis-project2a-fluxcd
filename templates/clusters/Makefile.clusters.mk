define MANAGED_CLUSTERS_FLUX
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: managed-clusters
  namespace: $(HMC_NAMESPACE)
spec:
  interval: 10m0s
  path: ./clusters
  prune: true
  sourceRef:
    kind: GitRepository
    name: $(FLUX_GIT_REPO_NAME)
    namespace: $(HMC_NAMESPACE)
endef
export MANAGED_CLUSTERS_FLUX

$(FLUX_MANAGEMENT_DIR)/managed-clusters.yaml: template_name = MANAGED_CLUSTERS_FLUX

GITOPS_MANAGED_CLUSTERS_DIR = $(LOCAL_GITOPS_REPO_PATH)/clusters
$(GITOPS_MANAGED_CLUSTERS_DIR):
	@mkdir -p $(GITOPS_MANAGED_CLUSTERS_DIR)
	@touch $(GITOPS_MANAGED_CLUSTERS_DIR)/.gitkeep

.PHONY: .generate-managed-clusters-config
.generate-managed-clusters-config: .fetch-repo $(GITOPS_MANAGED_CLUSTERS_DIR) $(FLUX_MANAGEMENT_DIR)/managed-clusters.yaml

.PHONY: .kubectl-apply-managed-clusters-config
.kubectl-apply-managed-clusters-config:
	$(call kubectl-apply,$(FLUX_MANAGEMENT_DIR)/managed-clusters.yaml)