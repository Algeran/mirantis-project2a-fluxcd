define HMC_SYSTEM
---
apiVersion: v1
kind: Namespace
metadata:
  name: $(HMC_NAMESPACE)
  labels:
    product.mirantis.com: hmc

---
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: $(FLUX_GIT_REPO_NAME)
  namespace: $(HMC_NAMESPACE)
spec:
  interval: 1m0s
  ref:
    branch: main
  url: https://github.com/$(GITHUB_USERNAME)/$(GITHUB_REPO_NAME).git

---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: hmc-system
  namespace: $(HMC_NAMESPACE)
spec:
  interval: 10m0s
  path: ./management/hmc-system
  prune: true
  sourceRef:
    kind: GitRepository
    name: $(FLUX_GIT_REPO_NAME)
endef
export HMC_SYSTEM

define HMC_OPERATOR
---
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: OCIRepository
metadata:
  name: hmc
  namespace: $(HMC_NAMESPACE)
spec:
  interval: 5m0s
  url: oci://ghcr.io/mirantis/hmc/charts/hmc
  ref:
    tag: $(HMC_VERSION)

---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: hmc
  namespace: $(HMC_NAMESPACE)
spec:
  chartRef:
    kind: OCIRepository
    name: hmc
    namespace: $(HMC_NAMESPACE)
  interval: 10m
  values:
    flux2:
      enabled: false
endef
export HMC_OPERATOR

define HMC_FLUX_NETWORKPOLICY
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-hmc-operator-interaction
  namespace: flux-system
spec:
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          product.mirantis.com: hmc
      podSelector:
        matchLabels:
          app.kubernetes.io/instance: hmc
    ports:
    - port: http
  podSelector:
    matchLabels:
      app: source-controller
  policyTypes:
  - Ingress
endef
export HMC_FLUX_NETWORKPOLICY


GITOPS_HMC_SYSTEM_DIR = $(LOCAL_GITOPS_REPO_PATH)/management/hmc-system
$(GITOPS_HMC_SYSTEM_DIR):
	@mkdir -p $(GITOPS_HMC_SYSTEM_DIR)

$(GITOPS_HMC_SYSTEM_DIR)/%: $(GITOPS_HMC_SYSTEM_DIR)
	$(call generate-template,$(template_name),$(GITOPS_HMC_SYSTEM_DIR),$(notdir $@))


$(FLUX_MANAGEMENT_DIR)/hmc-system.yaml: template_name = HMC_SYSTEM
$(GITOPS_HMC_SYSTEM_DIR)/hmc-operator.yaml: template_name = HMC_OPERATOR
$(GITOPS_HMC_SYSTEM_DIR)/hmc-flux-networkpolicy.yaml: template_name = HMC_FLUX_NETWORKPOLICY

.PHONY: .generate-hmc-system-manifests
.generate-hmc-system-manifests: .fetch-repo
	@for manifest in $(FLUX_MANAGEMENT_DIR)/hmc-system.yaml $(GITOPS_HMC_SYSTEM_DIR)/hmc-operator.yaml $(GITOPS_HMC_SYSTEM_DIR)/hmc-flux-networkpolicy.yaml ; do \
		make $$manifest ; \
	done

.PHONY: .kubectl-apply-hmc-system
.kubectl-apply-hmc-system:
	$(call kubectl-apply,$(FLUX_MANAGEMENT_DIR)/hmc-system.yaml)
