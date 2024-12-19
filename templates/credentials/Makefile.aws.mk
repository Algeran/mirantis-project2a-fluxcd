AWS_CREDENTIAL_NAME = aws-credential

define AWS_CREDENTIALS_FLUX
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
export AWS_CREDENTIALS_FLUX

define AWS_CREDENTIALS
---
apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
kind: AWSClusterStaticIdentity
metadata:
  name: aws-cluster-identity
spec:
  secretRef: aws-cluster-identity-secret
  allowedNamespaces: {}

---
apiVersion: hmc.mirantis.com/v1alpha1
kind: Credential
metadata:
  name: $(AWS_CREDENTIAL_NAME)
  namespace: hmc-system
spec:
  description: "Basic AWS credentials"
  identityRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
    kind: AWSClusterStaticIdentity
    name: aws-cluster-identity
endef
export AWS_CREDENTIALS

GITOPS_AWS_CREDENTIALS_DIR = $(LOCAL_GITOPS_REPO_PATH)/credentials/aws
$(GITOPS_AWS_CREDENTIALS_DIR):
	@mkdir -p $(GITOPS_AWS_CREDENTIALS_DIR)

$(GITOPS_AWS_CREDENTIALS_DIR)/%: $(GITOPS_AWS_CREDENTIALS_DIR)
	$(call generate-template,$(template_name),$(GITOPS_AWS_CREDENTIALS_DIR),$(notdir $@))

$(GITOPS_AWS_CREDENTIALS_DIR)/credentials.yaml: template_name = AWS_CREDENTIALS

.PHONY: .generate-aws-credentials-manifests
.generate-aws-credentials-manifests: $(GITOPS_AWS_CREDENTIALS_DIR)/credentials.yaml