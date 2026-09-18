resource "proxmox_virtual_environment_file" "this" {
  content_type = "snippets"
  datastore_id = var.cloud_datastore_id
  node_name    = var.node_name

  source_raw {
    data = <<-EOF
    #cloud-config
    hostname: ${var.hostname}
    timezone: ${var.timezone}
    users:
      - default
      - name: op
        groups:
          - sudo
        shell: /bin/bash
        ssh_authorized_keys:
          - ${trimspace(var.ssh_public_key)}
        sudo: ALL=(ALL) NOPASSWD:ALL
    package_update: true
    packages:
      - qemu-guest-agent
      - net-tools
      - curl
    runcmd:
      - systemctl enable qemu-guest-agent
      - systemctl start qemu-guest-agent
      - echo "done" > /tmp/cloud-config.done
    EOF

    file_name = "${var.hostname}-cloud-config.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "this" {
  name      = var.vm_name
  node_name = var.node_name

  agent {
    enabled = true
  }

  cpu {
    cores = var.cores
    type  = var.core_type
  }

  memory {
    dedicated = var.memory
  }

  disk {
    datastore_id = var.vm_datastore_id
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = var.disk_size
    import_from  = var.download_file_id
  }

  initialization {
    datastore_id = var.vm_datastore_id

    dns {
      servers = ["1.1.1.1", "8.8.8.8"]
    }

    ip_config {
      ipv4 {
        address = var.ipv4_address
        gateway = var.ipv4_gateway
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.this.id
  }

  network_device {
    bridge = var.bridge
  }

}


