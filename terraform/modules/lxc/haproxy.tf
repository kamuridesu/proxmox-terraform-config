resource "proxmox_virtual_environment_container" "haproxy_edge" {
  node_name    = "server"
  vm_id        = 200
  unprivileged = true

  initialization {
    hostname = "haproxy-edge"
    ip_config {
      ipv4 {
        address = "192.168.0.20/24"
        gateway = "192.168.0.1"
      }
    }
    user_account {
      keys = [var.ssh_pub_key]
    }
  }

  cpu {
    cores = 1
  }

  memory {
    dedicated = 512
    swap      = 0
  }

  disk {
    datastore_id = "local-btrfs"
    size         = 4
  }

  network_interface {
    name   = "veth0"
    bridge = "vmbr0"
  }

  operating_system {
    template_file_id = var.debian_12_template_id
    type             = "debian"
  }

  startup {
    order = "1"
  }

  start_on_boot = true


  tags = ["proxy"]
}

