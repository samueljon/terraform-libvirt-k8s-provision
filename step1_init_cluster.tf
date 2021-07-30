terraform {
  required_version = ">=0.14"
  required_providers {
    libvirt = {
      source  = "multani/libvirt"
      version = "0.6.3-1+4"
    }
  }
}

# https://fedoramagazine.org/setting-up-a-vm-on-fedora-server-using-cloud-images-and-virt-install-version-3/
# https://github.com/dmacvicar/terraform-provider-libvirt/blob/main/website/docs/r/domain.html.markdown
# https://github.com/dmacvicar/terraform-provider-libvirt/blob/main/examples/v0.13/count/main.tf
# https://yetiops.net/posts/proxmox-terraform-cloudinit-saltstack-prometheus/

provider "libvirt" {
  uri = "qemu:///system"
}

resource "libvirt_cloudinit_disk" "cloudinit_redhat" {
  name = "cloudinit_redhat.iso"
  pool = "default"

  user_data = <<EOF
#cloud-config
disable_root: 0
ssh_pwauth: 1

preserve_hostname: False
hostname: h7c-node-0x
fqdn: h7c-node-0x.villingaholt.nu

users:
  - name: samueljon
    groups: users,wheel
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh-authorized-keys:
      - ${file("public_ssh_keys/id_personal_ed25519.pub")}
  - name: ansible
    groups: wheel
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh-authorized-keys:
      - ${file("public_ssh_keys/id_personal_ansible_ed25519.pub")}

growpart:
  mode: auto
  devices: ['/']

package_upgrade: true

write_files:
  - path: /etc/modules-load.d/crio.conf
    content: |
      overlay
      br_netfilter

  - path: /etc/sysctl.d/99-kubernetes-cri.conf
    content: |
      net.bridge.bridge-nf-call-iptables  = 1
      net.bridge.bridge-nf-call-ip6tables = 1
      net.ipv4.ip_forward                 = 1
  
  - path: /etc/sysctl.d/k8s_arp.conf
    content: |
      net.ipv4.conf.all.arp_filter=1

  - path: /etc/default/grub
    content: |
      GRUB_TIMEOUT=1
      GRUB_DISTRIBUTOR="$(sed 's, release .*$,,g' /etc/system-release)"
      GRUB_DEFAULT=saved
      GRUB_DISABLE_SUBMENU=true
      GRUB_TERMINAL_OUTPUT="console"
      GRUB_CMDLINE_LINUX="systemd.unified_cgroup_hierarchy=0 no_timer_check net.ifnames=0 console=tty1 console=ttyS0,115200n8"
      GRUB_DISABLE_RECOVERY="true"
      GRUB_ENABLE_BLSCFG=true

  - path: /etc/hosts
    content: |
      127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
      ::1         localhost localhost.localdomain localhost6 localhost6.localdomain6

      192.168.88.241 h7c-node-1.villingaholt.nu h7c-node-1
      192.168.88.242 h7c-node-2.villingaholt.nu h7c-node-2
      192.168.88.243 h7c-node-3.villingaholt.nu h7c-node-3
      192.168.88.244 h7c-node-4.villingaholt.nu h7c-node-4

packages:
  - vim-enhanced
  - bash-completion
runcmd:
  # Recreate grub config with updated command line params
  - grub2-mkconfig -o /boot/grub2/grub.cfg
  # Enable kernel modules and systemparams
  - modprobe overlay br_netfilter
  - sysctl --system
  # Disable cloud-init after initial run
  - systemctl  disable  cloud-init
  # Set selinux to permissive mode
  - setenforce 0
  - sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
  # Install and activate cri-o
  - dnf module enable cri-o:1.20 -y 
  - dnf install cri-o -y
  - systemctl daemon-reload
  - systemctl enable crio --now
  # Turn off SWAP settings
  - touch /etc/systemd/zram-generator.conf
  # reboot the host once completed
  - reboot 
EOF

}

resource "libvirt_volume" "fc34_master_image" {
  name   = "fc34_master_image.qcow2"
  source = "https://download.fedoraproject.org/pub/fedora/linux/releases/34/Cloud/x86_64/images/Fedora-Cloud-Base-34-1.2.x86_64.qcow2"
  format = "qcow2"
}

resource "libvirt_volume" "volume" {
  name           = "h7c-node-${count.index + 1 + var.node_offset }.villingaholt.nu.qcow2"
  base_volume_id = libvirt_volume.fc34_master_image.id
  size           = var.node_disk_size
  count          = var.number_of_nodes
}

resource "libvirt_domain" "domain" {
  count = var.number_of_nodes
  name = "h7c-node-${count.index  + 1 + var.node_offset }.villingaholt.nu"
  memory = var.node_memory
  vcpu   = var.node_vcpu
  qemu_agent = true

  cloudinit = libvirt_cloudinit_disk.cloudinit_redhat.id

  disk {
    volume_id = element(libvirt_volume.volume.*.id, count.index)
  }

  network_interface {
    hostname       = "h7c-node-${count.index + 1  + var.node_offset }.villingaholt.nu"
    network_name   = "default"
    mac            = "52:54:00:7e:30:0${count.index + 1  + var.node_offset }"
    wait_for_lease = true
  }

  console {
    type        = "pty"
    target_type = "virtio"
    target_port = "0"
  }

  graphics {
    type        = "vnc"
    autoport    = true
    listen_type = "address"
    listen_address = "127.0.0.1"
  }

}

output "ips" {
  value = libvirt_domain.domain.*.network_interface.0.addresses
}