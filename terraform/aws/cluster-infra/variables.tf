variable "user" {
  description = "the owner of the provisioned infra"
  type        = string
  default     = ""
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "vpc_cidr_block" {
  description = "AWS VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr_block" {
  description = "AWS subnet CIDR"
  type        = string
  default     = "10.0.1.0/24"
}

variable "management_cluster_instance_type" {
  description = "EC2 instance type where the management cluster node will be deployed"
  type        = string
  default     = "m5.large"
}
