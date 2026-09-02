terraform {
  required_version = ">= 1.5"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.111.0"
    }
  }
}

provider "proxmox" {
  endpoint  = var.endpoint
  api_token = var.api_token

  ssh {
    agent    = true
    username = var.username
    node {
      name    = "pve"
      address = var.pve_ip
    }
  }
}
