terraform {
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
      version = "0.6.12"
    }
  }
}

# https://fedoramagazine.org/setting-up-a-vm-on-fedora-server-using-cloud-images-and-virt-install-version-3/
# https://github.com/dmacvicar/terraform-provider-libvirt/blob/main/website/docs/r/domain.html.markdown
# https://github.com/dmacvicar/terraform-provider-libvirt/blob/main/examples/v0.13/count/main.tf
# https://yetiops.net/posts/proxmox-terraform-cloudinit-saltstack-prometheus/
# https://www.server-world.info/en/note?os=Fedora_34&p=kubernetes&f=1

provider "libvirt" {
  uri = "qemu:///system"
}

resource "libvirt_cloudinit_disk" "cloudinit_k8s" {
  name = "cloudinit_k8s.iso"
  pool = "default"

  #meta_data = data.template_file.meta_config.rendered
  user_data = data.template_file.user_data.rendered
  network_config = data.template_file.network_config.rendered
}


data "template_file" "user_data" {
  template = file("${path.module}/cloud-init/cloud_init.cfg")
}

data "template_file" "network_config" {
  template = file("${path.module}/cloud-init/network_config.cfg")
}

data "template_file" "meta_config" {
  template = file("${path.module}/cloud-init/meta.cfg")
}

resource "libvirt_volume" "fc35_master_image" {
  name   = "fc35_master_image.qcow2"
  source = "https://download.fedoraproject.org/pub/fedora/linux/releases/35/Cloud/x86_64/images/Fedora-Cloud-Base-35-1.2.x86_64.qcow2"
  format = "qcow2"
}

resource "libvirt_volume" "volume" {
  name           = "${var.host_prefix}${count.index + 1 + var.node_offset }.${var.base_domain}.qcow2"
  base_volume_id = libvirt_volume.fc35_master_image.id
  size           = var.node_disk_size
  count          = var.number_of_nodes
}

resource "libvirt_domain" "domain" {
  count       = var.number_of_nodes
  name        = "${var.host_prefix}${count.index  + 1 + var.node_offset }.${var.base_domain}"
  memory      = var.node_memory
  vcpu        = var.node_vcpu
  qemu_agent  = true

  cloudinit = libvirt_cloudinit_disk.cloudinit_k8s.id

  disk {
    volume_id = element(libvirt_volume.volume.*.id, count.index)
  }

  network_interface {
    hostname       = "${var.host_prefix}${count.index + 1  + var.node_offset }.${var.base_domain}"
    network_name   = "default"
    mac            = "${var.mac_address_pattern}${count.index + 1  + var.node_offset }"
    wait_for_lease = true
  }
  
  console {
    type        = "pty"
    target_type = "virtio"
    target_port = "0"
  }

  graphics {
    type           = "vnc"
    autoport       = true
    listen_type    = "address"
    listen_address = "127.0.0.1"
  }

}

output "ips" {
  value = libvirt_domain.domain.*.network_interface.0.addresses
}
