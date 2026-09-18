resource "proxmox_download_file" "debian13" {
  content_type = "import"
  datastore_id = proxmox_storage_directory.local.id
  node_name    = "pve"
  file_name    = "debian-13-generic-amd64.qcow2"
  url          = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2"
}

###--- STORAGE CONFIGURATION ---###

import {
  to = proxmox_storage_directory.local
  id = "local"
}

resource "proxmox_storage_directory" "local" {
  id      = "local"
  path    = "/var/lib/vz"
  content = ["iso", "vztmpl", "backup", "snippets", "import"]
}

resource "proxmox_storage_lvmthin" "data" {
  id           = "local-lvmthin"
  nodes        = ["pve"]
  volume_group = "vg0"
  thin_pool    = "data"
  content      = ["images", "rootdir"]
}

###--- CLUSTER TEST ---###

module "k3s-server" {
  source           = "../modules/k3s-node-vm/"
  ssh_public_key   = file("./config/id_dev.pub")
  cores            = 2
  memory           = 4096
  hostname         = "k3s-server"
  ipv4_address     = "10.11.0.10/24"
  ipv4_gateway     = "10.11.0.1"
  vm_name          = "k3s-server"
  download_file_id = proxmox_download_file.debian13.id
  vm_datastore_id  = proxmox_storage_lvmthin.data.id
}

module "node_vm" {
  count = 2

  source           = "../modules/k3s-node-vm/"
  ssh_public_key   = file("./config/id_dev.pub")
  cores            = 2
  memory           = 4096
  hostname         = "k3s-agent-${count.index + 1}"
  ipv4_address     = "10.11.0.${count.index + 11}/24"
  ipv4_gateway     = "10.11.0.1"
  vm_name          = "k3s-agent-${count.index + 1}"
  download_file_id = proxmox_download_file.debian13.id
  vm_datastore_id  = proxmox_storage_lvmthin.data.id
}
