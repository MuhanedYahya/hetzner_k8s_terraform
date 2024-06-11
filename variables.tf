variable "hcloud_token" {
  description = "Hetzner Cloud API Token"
  type        = string
}

variable "masters_count" {
  description = "Number of master nodes"
  type        = number
}

variable "workers_count" {
  description = "Number of worker nodes"
  type        = number
}

variable "cni" {
  description = "CNI plugin (flannel or cilium)"
  type        = string
  default     = "flannel"
}

variable "master_type" {
  description = "Hetzner Cloud server type for master nodes"
  type        = string
  default     = "cx21"
}

variable "worker_type" {
  description = "Hetzner Cloud server type for worker nodes"
  type        = string
  default     = "cx11"
}

variable "image" {
  description = "Image type for the nodes"
  type        = string
  default     = "ubuntu-20.04"
}

variable "kubernetes_api_dns" {
  description = "Kubernetes API DNS name (optional)"
  type        = string
  default     = ""
}

variable "kubernetes_api_port" {
  description = "Kubernetes API DNS name (optional)"
  type        = string
  default     = "6433"
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key file"
}

variable "ssh_private_key_path" {
  description = "Path to the SSH public key file"
}