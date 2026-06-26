resource "proxmox_download_file" "debian_12_template" {
  content_type = "vztmpl"
  datastore_id = "local-btrfs"
  node_name    = "server"
  url          = "http://download.proxmox.com/images/system/debian-12-standard_12.12-1_amd64.tar.zst"
}
