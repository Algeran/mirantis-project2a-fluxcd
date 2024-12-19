define AWS_STANDALONE_0_0_4_CLUSTER
---
apiVersion: hmc.mirantis.com/v1alpha1
kind: ManagedCluster
metadata:
  name: managed-standalone-aws-$(USERNAME)
  namespace: $(HMC_NAMESPACE)
spec:
  template: aws-standalone-cp-0-0-4
  credential: $(AWS_CREDENTIAL_NAME)
  dryRun: false
  config:
    region: us-west-2
    controlPlaneNumber: 1
    workersNumber: 2
    controlPlane:
      instanceType: t3.small
    worker:
      instanceType: t3.small
endef
export AWS_STANDALONE_0_0_4_CLUSTER

define AWS_STANDALONE_0_0_4_CLUSTER_INGRESS
---
apiVersion: hmc.mirantis.com/v1alpha1
kind: ManagedCluster
metadata:
  name: managed-standalone-aws-$(USERNAME)
  namespace: $(HMC_NAMESPACE)
spec:
  template: aws-standalone-cp-0-0-4
  credential: $(AWS_CREDENTIAL_NAME)
  dryRun: false
  config:
    region: us-west-2
    controlPlaneNumber: 1
    workersNumber: 2
    controlPlane:
      instanceType: t3.small
    worker:
      instanceType: t3.small
  services:
    - template: ingress-nginx-4-11-0
      name: ingress-nginx
      namespace: ingress-nginx
endef
export AWS_STANDALONE_0_0_4_CLUSTER_INGRESS

$(GITOPS_MANAGED_CLUSTERS_DIR)/aws:
	@mkdir -p $(GITOPS_MANAGED_CLUSTERS_DIR)/aws

$(GITOPS_MANAGED_CLUSTERS_DIR)/aws/%: $(GITOPS_MANAGED_CLUSTERS_DIR)/aws
	$(call generate-template,$(template_name),$(GITOPS_MANAGED_CLUSTERS_DIR)/aws,$(notdir $@))

$(GITOPS_MANAGED_CLUSTERS_DIR)/aws/standalone-0.0.4.yaml: template_name = AWS_STANDALONE_0_0_4_CLUSTER

.PHONY: .generate-aws-standalone-0-0-4-manifest
.generate-aws-standalone-0-0-4-manifest: .fetch-repo $(GITOPS_MANAGED_CLUSTERS_DIR)/aws/standalone-0.0.4.yaml

.PHONY: .generate-aws-standalone-0-0-4-with-ingress
.generate-aws-standalone-0-0-4-with-ingress: .fetch-repo $(GITOPS_MANAGED_CLUSTERS_DIR)/aws/standalone-0.0.4.yaml
	$(call generate-template,AWS_STANDALONE_0_0_4_CLUSTER_INGRESS,$(GITOPS_MANAGED_CLUSTERS_DIR)/aws,standalone-0.0.4.yaml)
