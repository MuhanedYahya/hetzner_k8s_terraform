provider "hcloud" {
  token = var.hcloud_token
}

resource "hcloud_ssh_key" "hcloud_ssh_public_key" {
  name       = "k8s-ssh-key"
  public_key = file(var.ssh_public_key_path)
}

# define hcloud network & subnet
resource "hcloud_network" "k8s_network" {
  name     = "example-network"
  ip_range = "10.0.0.0/16"
}
resource "hcloud_network_subnet" "k8s_subnet" {
  network_id   = hcloud_network.k8s_network.id
  type         = "cloud"
  network_zone = "eu-central"
  ip_range     = "10.0.0.0/16"
}



# master nodes
resource "hcloud_server" "masters" {
  count       = var.masters_count
  name        = "k8s-master-${count.index + 1}"
  image       = var.image
  server_type = var.master_type
  ssh_keys    = [hcloud_ssh_key.hcloud_ssh_public_key.id]
  network {
    network_id = hcloud_network_subnet.k8s_subnet.network_id
  }
  connection {
    type        = "ssh"
    user        = "root"
    private_key = file(var.ssh_private_key_path)
    host        = self.ipv4_address
  }
  provisioner "file" {
    source      = "init.sh"
    destination = "/tmp/init.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/init.sh",
      "/tmp/init.sh",
      "hostnamectl set-hostname k8s-master-${count.index + 1}",
      "echo '127.0.0.1 k8s-master-${count.index + 1}' >> /etc/hosts"
    ]
  }

}

# init first master (kubeadm init)
resource "null_resource" "init_first_master" {
  count      = var.masters_count > 0 ? 1 : 0
  depends_on = [hcloud_server.masters]
  connection {
    type        = "ssh"
    user        = "root"
    private_key = file(var.ssh_private_key_path)
    host        = hcloud_server.masters[0].ipv4_address
  }
  provisioner "remote-exec" {
    # --ignore-preflight-errors=NumCPU in order to use smaller type than CX21 current type is CX11; 2VCpus is required for k8s
    # --pod-network-cidr must match CNI's cidr
    inline = [
      "sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --cri-socket=/run/containerd/containerd.sock --ignore-preflight-errors=NumCPU",
      "mkdir -p /root/.kube",
      "sudo cp -i /etc/kubernetes/admin.conf /root/.kube/config",
      "sudo chown $(id -u):$(id -g) /root/.kube/config"
    ]
  }
  # add public key
  provisioner "remote-exec" {
    inline = [
      <<-EOF
        cat >>~/.ssh/authorized_keys<<EOKEY
        ${file(var.ssh_public_key_path)}
        EOKEY
      EOF
    ]
  }

}

# add secondary masters
resource "null_resource" "join_other_masters" {
  count      = var.masters_count > 1 ? var.masters_count - 1 : 0
  depends_on = [null_resource.init_first_master]
  connection {
    type        = "ssh"
    user        = "root"
    private_key = file(var.ssh_private_key_path)
    host        = hcloud_server.masters[count.index + 1].ipv4_address
  }

  provisioner "file" {
    source      = "keys/id_ed25519"
    destination = "/tmp/id_ed25519"
  }

  # add private key
  provisioner "remote-exec" {
    inline = [
      "cp /tmp/id_ed25519 ~/.ssh/",
      "chmod 400 ~/.ssh/id_ed25519",
    ]
  }


  # join cluster as master
  provisioner "remote-exec" {
    inline = [
      "JOIN_CMD=$(ssh -o StrictHostKeyChecking=no root@${hcloud_server.masters[0].ipv4_address} 'kubeadm --kubeconfig=/etc/kubernetes/admin.conf token create --print-join-command')",
      "CA_CERT_HASH=$(ssh -o StrictHostKeyChecking=no root@${hcloud_server.masters[0].ipv4_address} 'openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl pkey -pubin -outform der | openssl dgst -sha256 -hex | sed 's/^.* //')",
      "sudo $JOIN_CMD --control-plane --discovery-token-ca-cert-hash sha256:$CA_CERT_HASH --cri-socket=/run/containerd/containerd.sock"
    ]
  }

}

# worker nodes
resource "hcloud_server" "workers" {
  count       = var.workers_count
  name        = "k8s-worker-${count.index + 1}"
  image       = var.image
  server_type = var.worker_type
  ssh_keys    = [hcloud_ssh_key.hcloud_ssh_public_key.id]
  depends_on = [null_resource.install_cni]
  network {
    network_id = hcloud_network_subnet.k8s_subnet.network_id
  }
  connection {
    type        = "ssh"
    user        = "root"
    private_key = file(var.ssh_private_key_path)
    host        = self.ipv4_address
  }
  provisioner "file" {
    source      = "init.sh"
    destination = "/tmp/init.sh"
  }

  provisioner "file" {
    source      = "keys/id_ed25519"
    destination = "/tmp/id_ed25519"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/init.sh",
      "/tmp/init.sh",
      "hostnamectl set-hostname k8s-worker-${count.index + 1}",
      "echo '127.0.0.1 k8s-worker-${count.index + 1}' >> /etc/hosts"
    ]
  }

  provisioner "remote-exec" {
    inline = [
      "cp /tmp/id_ed25519 ~/.ssh/",
      "chmod 400 ~/.ssh/id_ed25519",
    ]
  }

  # join cluster as worker
  provisioner "remote-exec" {
    inline = [
      "JOIN_CMD=$(ssh -o StrictHostKeyChecking=no root@${hcloud_server.masters[0].ipv4_address} 'kubeadm --kubeconfig=/etc/kubernetes/admin.conf token create --print-join-command')",
      "$JOIN_CMD"
    ]
  }
}


# CNI installation flannel/cilium
resource "null_resource" "install_cni" {
  count = var.masters_count > 0 ? 1 : 0

  # add CNI files
  provisioner "file" {
    source      = "cni/flannel.sh"
    destination = "/tmp/flannel.sh"
  }
  provisioner "file" {
    source      = "cni/flannel.sh"
    destination = "/tmp/cilium.sh"
  }
  # add 

  # install helm
  provisioner "remote-exec" {
    inline = [
      "curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3",
      "chmod 700 get_helm.sh",
      "./get_helm.sh"
    ]
  }

  # install CNI
  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/flannel.sh",
      "chmod +x /tmp/cilium.sh",
      "/tmp/${var.cni}.sh"
    ]
  }

  depends_on = [null_resource.init_first_master]
  connection {
    type        = "ssh"
    user        = "root"
    private_key = file(var.ssh_private_key_path)
    host        = hcloud_server.masters[0].ipv4_address
  }
}


resource "null_resource" "update_hosts" {
  count = var.masters_count + var.workers_count

  provisioner "remote-exec" {
    inline = [
      "cat <<EOF | sudo tee -a /etc/hosts",
      "${join("\n", [
        for i, master in hcloud_server.masters : "${master.ipv4_address} k8s-master-${i + 1}"
      ])}",
      "${join("\n", [
        for i, worker in hcloud_server.workers : "${worker.ipv4_address} k8s-worker-${i + 1}"
      ])}",
      "EOF"
    ]
  }

  depends_on = [hcloud_server.masters, hcloud_server.workers]

  connection {
    type        = "ssh"
    user        = "root"
    private_key = file(var.ssh_private_key_path)
    host        = element(concat(hcloud_server.masters[*].ipv4_address, hcloud_server.workers[*].ipv4_address), count.index)
  }
}


# OUTPUTS

output "master_ips" {
  value       = hcloud_server.masters.*.ipv4_address
  description = "IP addresses of the master nodes"
}

output "worker_ips" {
  value       = hcloud_server.workers.*.ipv4_address
  description = "IP addresses of the worker nodes"
}