terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.101.0"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox_url
  # api_token = var.pve_api_token
  username = "root@pam"
  password = var.proxmox_root_password
  insecure = true
  ssh {
    agent = true
  }
}

