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
# https://www.server-world.info/en/note?os=Fedora_34&p=kubernetes&f=1

provider "libvirt" {
  uri = "qemu+ssh:///system"
}

resource "libvirt_cloudinit_disk" "cloudinit_k8s" {
  name = "cloudinit_k8s.iso"
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
      - ${file("../public_ssh_keys/id_personal_ed25519.pub")}
  - name: ansible
    groups: wheel
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh-authorized-keys:
      - ${file("../public_ssh_keys/id_personal_ansible_ed25519.pub")}

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
      net.ipv6.conf.all.forwarding        = 1
  
  - path: /etc/sysctl.d/k8s_arp.conf
    content: |
      net.ipv4.conf.all.arp_filter=1

  - path: /etc/yum.repos.d/kubernetes.repolist
    content: |
      [kubernetes]
      name=Kubernetes
      baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
      enabled=1
      gpgcheck=1
      repo_gpgcheck=1
      gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
      exclude=kubelet kubeadm kubectl

  #- path: /etc/default/grub
  #  content: |
  #    GRUB_TIMEOUT=1
  #    GRUB_DISTRIBUTOR="$(sed 's, release .*$,,g' /etc/system-release)"
  #    GRUB_DEFAULT=saved
  #    GRUB_DISABLE_SUBMENU=true
  #    GRUB_TERMINAL_OUTPUT="console"
  #    GRUB_CMDLINE_LINUX="systemd.unified_cgroup_hierarchy=0 no_timer_check net.ifnames=0 console=tty1 console=ttyS0,115200n8"
  #    GRUB_DISABLE_RECOVERY="true"
  #    GRUB_ENABLE_BLSCFG=true

  - path: /etc/hosts
    content: |
      127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
      ::1         localhost localhost.localdomain localhost6 localhost6.localdomain6

      #192.168.88.241 h7c-node-1.villingaholt.nu h7c-node-1
      #192.168.88.242 h7c-node-2.villingaholt.nu h7c-node-2
      #192.168.88.243 h7c-node-3.villingaholt.nu h7c-node-3
      #192.168.88.244 h7c-node-4.villingaholt.nu h7c-node-4

packages:
  - vim-enhanced
  - bash-completion
  - nfs-utils
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
  - dnf check-update
  - dnf module enable cri-o:1.22 -y 
  - dnf install cri-o -y
  - systemctl daemon-reload
  - systemctl enable crio --now
  # Install k8s components
  - yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
  - systemctl enable --now kubelet
  # Turn off SWAP settings
  #- touch /etc/systemd/zram-generator.conf
  # reboot the host once completed
  - reboot 
EOF

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