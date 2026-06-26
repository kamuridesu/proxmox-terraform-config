module "lxc" {
  source                = "./modules/lxc"
  ssh_pub_key           = var.ssh_pub_key
  debian_12_template_id = proxmox_download_file.debian_12_template.id
}
