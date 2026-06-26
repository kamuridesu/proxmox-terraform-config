resource "proxmox_virtual_environment_container" "db_stack" {
  node_name    = "server"
  vm_id        = 203
  unprivileged = true

  initialization {
    hostname = "db-stack"
    ip_config {
      ipv4 {
        address = "192.168.0.23/24"
        gateway = "192.168.0.1"
      }
    }
    user_account {
      keys = [var.ssh_pub_key]
    }
  }

  cpu {
    cores = 2
  }

  memory {
    dedicated = 1024
    swap      = 512
  }

  disk {
    datastore_id = "local-btrfs"
    size         = 10
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
    order = "2"
  }

  start_on_boot = true
  tags          = ["database"]
}
