# Fedora 35 bootstrap for kubernetes on KVM host

This is a bootstrap for Fedora Core 35 ( Cloud Image ) on a kvm host using libvirt provider. This plan basically installs the operating system and does some initial configuration with cloud-init so that the nodes are ready for running nessecary steps for adding kubernetes repo's and tools and run k8s bootstrapping with kubeadm. 

```shell
# Standard lifecycle with default values
cd terraform
terraform init
terraform plan
terraform apply
terraform destroy

# with parameters
terraform init
# This results in creating 8 nodes starting from number 10
# The default values for offset is 0 and default number of nodes are 2
terraform plan -var node_offset=10 -var number_of_nodes=8
terraform apply -var node_offset=10 -var number_of_nodes=8
```
