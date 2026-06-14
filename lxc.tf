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
    template_file_id = proxmox_download_file.debian_12_template.id
    type             = "debian"
  }

  startup {
    order = "1"
  }

  start_on_boot = true


  tags = ["proxy"]
}

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
    template_file_id = proxmox_download_file.debian_12_template.id
    type             = "debian"
  }

  startup {
    order    = "2"
    up_delay = "10"
  }

  start_on_boot = true


  tags = ["media", "dockerable"]
}

resource "proxmox_virtual_environment_container" "services_stack" {
  node_name    = "server"
  vm_id        = 202
  unprivileged = true

  features {
    nesting = true
  }

  initialization {
    hostname = "services-stack"
    ip_config {
      ipv4 {
        address = "192.168.0.22/24"
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
    dedicated = 1024
    swap      = 512
  }

  disk {
    datastore_id = "local-btrfs"
    size         = 20
  }

  network_interface {
    name   = "veth0"
    bridge = "vmbr0"
  }

  operating_system {
    template_file_id = proxmox_download_file.debian_12_template.id
    type             = "debian"
  }

  startup {
    order = "3"
  }

  start_on_boot = true


  tags = ["services", "dockerable"]
}

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
    template_file_id = proxmox_download_file.debian_12_template.id
    type             = "debian"
  }

  startup {
    order = "2"
  }

  start_on_boot = true
  tags          = ["database"]
}
