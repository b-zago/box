
locals {
  clusters = {
    staging = {
      k3s_version = "v1.36.3+k3s1"
      server      = { cores = 2, memory = 4096, ip = "10.10.10.11" }
      agents      = { cores = 2, memory = 4096, ips = ["10.10.10.12", "10.10.10.13"] }
    }
    prod = {
      k3s_version = "v1.36.3+k3s1"
      server      = { cores = 2, memory = 4096, ip = "10.10.10.21" }
      agents      = { cores = 3, memory = 12288, ips = ["10.10.10.22", "10.10.10.23"] }
    }
  }

  nodes = merge([
    for cname, c in local.clusters : merge(
      {
        "${cname}-server" = {
          cluster = cname
          role    = "server"
          cores   = c.server.cores
          memory  = c.server.memory
          ip      = c.server.ip
        }
      },
      {
        for i, ip in try(c.agents.ips, []) : "${cname}-agent-${i + 1}" => {
          cluster = cname
          role    = "agent"
          cores   = c.agents.cores
          memory  = c.agents.memory
          ip      = ip
        }
      }
    )
  ]...)

  enable_postgres = true
}

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



module "k3s_node" {
  for_each = local.nodes

  source           = "../modules/k3s-node-vm/"
  ssh_public_key   = file("./config/id_hetz.pub")
  cores            = each.value.cores
  memory           = each.value.memory
  hostname         = each.key
  vm_name          = each.key
  ipv4_address     = "${each.value.ip}/24"
  download_file_id = proxmox_download_file.debian13.id
}

module "postgresql" {
  count = local.enable_postgres ? 1 : 0

  source           = "../modules/k3s-node-vm/"
  ssh_public_key   = file("./config/id_hetz.pub")
  cores            = 2
  memory           = 4096
  hostname         = "postgresql"
  ipv4_address     = "10.10.10.50/24"
  vm_name          = "postgresql"
  download_file_id = proxmox_download_file.debian13.id
}



resource "local_file" "k3s_inventory" {
  for_each = local.clusters

  content = templatefile("${path.module}/templates/k3s_inventory.tpl", {
    server_name = module.k3s_node["${each.key}-server"].hostname
    server_ip   = each.value.server.ip
    agents = [
      for k, n in local.nodes : { name = k, ip = n.ip }
      if n.cluster == each.key && n.role == "agent"
    ]
    pg_ip       = local.enable_postgres ? split("/", module.postgresql[0].ipv4_address)[0] : null
    k3s_version = each.value.k3s_version
  })

  filename = "${path.module}/../../../ansible/inventory/${each.key}/inventory.ini"
}
