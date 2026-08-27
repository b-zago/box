###--- MINECRAFT FOR NOW ---###
resource "proxmox_download_file" "debian13" {
  content_type = "import"
  datastore_id = "local"
  node_name    = "pve"
  file_name    = "debian-13-generic-amd64.qcow2"
  url          = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2"
}

resource "proxmox_virtual_environment_vm" "minecraft" {
  name      = "minecraft"
  node_name = "pve"
  vm_id     = 101

  # cloud image has no qemu-guest-agent yet — install it manually, then flip this on
  agent {
    enabled = true
  }
  stop_on_destroy = true

  cpu {
    cores = 4
    type  = "host"
  }

  memory {
    dedicated = 16384
  }

  disk {
    datastore_id = "local-lvm"
    import_from  = proxmox_download_file.debian13.id
    interface    = "virtio0"
    size         = 80
    iothread     = true
    discard      = "on"
  }

  initialization {
    datastore_id = "local-lvm"

    ip_config {
      ipv4 {
        address = "10.10.10.10/24"
        gateway = "10.10.10.1"
      }
    }

    dns {
      servers = ["1.1.1.1", "8.8.8.8"]
    }

    user_account {
      username = "debian"
      keys     = [trimspace(file("~/.ssh/id_hetz.pub"))]
    }
  }

  network_device {
    bridge = "vmbr0"
  }
}


###--- CLUSTER TEST ---###

module "k3s-server" {
  source           = "../modules/k3s-node-vm/"
  ssh_public_key   = file("./config/id_hetz.pub")
  cores            = 2
  memory           = 4096
  hostname         = "k3s-server"
  ipv4_address     = "10.10.10.11/24"
  vm_name          = "k3s-server"
  download_file_id = proxmox_download_file.debian13.id
}

module "node_vm" {
  count = 2

  source           = "../modules/k3s-node-vm/"
  ssh_public_key   = file("./config/id_hetz.pub")
  cores            = 3
  memory           = 12288
  hostname         = "k3s-agent-${count.index + 1}"
  ipv4_address     = "10.10.10.${count.index + 12}/24"
  vm_name          = "k3s-agent-${count.index + 1}"
  download_file_id = proxmox_download_file.debian13.id
}
