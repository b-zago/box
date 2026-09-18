variable "cloud_datastore_id" {
  type        = string
  default     = "local"
  description = "Datastore ID"
}

variable "node_name" {
  type        = string
  default     = "pve"
  description = "Node name"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH Public Key content"
}

variable "timezone" {
  type    = string
  default = "Europe/Warsaw"
}

variable "hostname" {
  type = string
}

variable "vm_name" {
  type = string

}


###--- VM SETTINGS ---###

variable "cores" {
  type = number
}

variable "memory" {
  type = number
}

variable "vm_datastore_id" {
  type    = string
  default = "local-lvm"
}

variable "disk_size" {
  type    = number
  default = 40
}

variable "ipv4_address" {
  type = string
}

variable "ipv4_gateway" {
  type    = string
  default = "10.10.10.1"
}

variable "bridge" {
  type    = string
  default = "vmbr0"
}

variable "core_type" {
  type        = string
  default     = "host"
  description = "Core type for CPU. Default here to `host` but qemu64 default is also an option"

}

variable "download_file_id" {
  type = string

}
