variable "number_of_nodes" {
  type = string
  default = "2"
}

variable "node_offset" {
  type = string
  default = "0"
}

variable "node_memory" {
  type = string
  default = "8192"
}

variable "node_vcpu" {
  type = string
  default = "4"
}

variable "node_disk_size" {
  type = string
  default = "42949672960"
}

variable "mac_address_pattern" {
  type = string
  default = "52:54:00:7e:30:0"
}