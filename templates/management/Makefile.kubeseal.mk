define KUBESEAL_FLUX
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: sealed-secrets
  namespace: $(HMC_NAMESPACE)
spec:
  interval: 10m0s
  path: ./management/sealed-secrets
  prune: true
  sourceRef:
    kind: GitRepository
    name: $(FLUX_GIT_REPO_NAME)
    namespace: $(HMC_NAMESPACE)
endef
export KUBESEAL_FLUX

define KUBESEAL_OPERATOR
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: sealed-secrets
  namespace: $(HMC_NAMESPACE)
spec:
  interval: 1h0m0s
  url: https://bitnami-labs.github.io/sealed-secrets

---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: sealed-secrets
  namespace: $(HMC_NAMESPACE)
spec:
  chart:
    spec:
      chart: sealed-secrets
      sourceRef:
        kind: HelmRepository
        name: sealed-secrets
      version: ">=1.15.0-0"
  interval: 1h0m0s
  releaseName: sealed-secrets-controller
  targetNamespace: $(HMC_NAMESPACE)
  install:
    crds: Create
  upgrade:
    crds: CreateReplace
endef
export KUBESEAL_OPERATOR

GITOPS_KUBESEAL_DIR = $(LOCAL_GITOPS_REPO_PATH)/management/sealed-secrets
$(GITOPS_KUBESEAL_DIR):
	@mkdir -p $(GITOPS_KUBESEAL_DIR)

$(GITOPS_KUBESEAL_DIR)/%: $(GITOPS_KUBESEAL_DIR)
	$(call generate-template,$(template_name),$(GITOPS_KUBESEAL_DIR),$(notdir $@))


$(FLUX_MANAGEMENT_DIR)/sealed-secrets.yaml: template_name = KUBESEAL_FLUX
$(GITOPS_KUBESEAL_DIR)/sealed-secrets.yaml: template_name = KUBESEAL_OPERATOR

.PHONY: .generate-kubeseal-manifests
.generate-kubeseal-manifests: .fetch-repo
	@for manifest in $(FLUX_MANAGEMENT_DIR)/sealed-secrets.yaml $(GITOPS_KUBESEAL_DIR)/sealed-secrets.yaml ; do \
		make $$manifest ; \
	done

.PHONY: .kubectl-apply-kubeseal
.kubectl-apply-kubeseal:
	$(call kubectl-apply,$(FLUX_MANAGEMENT_DIR)/sealed-secrets.yaml)