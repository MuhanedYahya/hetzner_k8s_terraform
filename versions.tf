terraform {
  required_providers {
    hcloud = {
      source = "hetznercloud/hcloud"
    }
  }
  # new version is required
  required_version = ">= 0.13"
}
