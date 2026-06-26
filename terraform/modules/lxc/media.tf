resource "proxmox_virtual_environment_container" "media_stack" {
  node_name    = "server"
  vm_id        = 201
  unprivileged = true

  features {
    nesting = true
  }

  initialization {
    hostname = "media-stack"
    ip_config {
      ipv4 {
        address = "192.168.0.21/24"
        gateway = "192.168.0.1"
      }
    }
    user_account {
      keys = [var.ssh_pub_key]
    }
  }

  cpu {
    cores = 4
  }

  memory {
    dedicated = 4096
    swap      = 512
  }

  disk {
    datastore_id = "local-btrfs"
    size         = 50
  }

  network_interface {
    name   = "veth0"
    bridge = "vmbr0"
  }

  device_passthrough {
    path = "/dev/dri/card0"
    mode = "0666"
  }

  device_passthrough {
    path = "/dev/dri/renderD128"
    mode = "0666"
  }

  mount_point {
    volume = "/mnt/amenohabakiri"
    path   = "/media/AMENOHABAKIRI"
  }

  operating_system {
    template_file_id = var.debian_12_template_id
    type             = "debian"
  }

  startup {
    order    = "2"
    up_delay = "10"
  }

  start_on_boot = true


  tags = ["media", "dockerable"]
}

