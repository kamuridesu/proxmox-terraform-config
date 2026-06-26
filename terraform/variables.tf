variable "ssh_pub_key" {
  type        = string
  sensitive   = true
  nullable    = false
  description = "VM ssh pub key"
}

variable "proxmox_url" {
  type        = string
  sensitive   = true
  nullable    = false
  description = "Proxmox URL"
}

variable "proxmox_root_password" {
  type        = string
  sensitive   = true
  nullable    = true
  description = "Proxmox root password"
}
