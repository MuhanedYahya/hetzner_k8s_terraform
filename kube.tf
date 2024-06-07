provider "hcloud" {
  token = var.hcloud_token
}

# tls and ssh keys
resource "tls_private_key" "tls" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
resource "hcloud_ssh_key" "hcloud_ssh_public_key" {
  name       = "k8s-ssh-key"
  public_key = tls_private_key.tls.public_key_openssh
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
    private_key = tls_private_key.tls.private_key_pem
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
  depends_on = [hcloud_server.masters, tls_private_key.tls]
  connection {
    type        = "ssh"
    user        = "root"
    private_key = tls_private_key.tls.private_key_pem
    host        = hcloud_server.masters[0].ipv4_address
  }
  provisioner "remote-exec" {
    # --ignore-preflight-errors=NumCPU in order to use smaller type than CX21 current type is CX11; 2VCpus is required for k8s
    inline = [
      "sudo kubeadm init --pod-network-cidr=10.0.0.0/16 --cri-socket=/run/containerd/containerd.sock --ignore-preflight-errors=NumCPU",
      "mkdir -p $HOME/.kube",
      "sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config",
      "sudo chown $(id -u):$(id -g) $HOME/.kube/config"
    ]
  }

  provisioner "remote-exec" {
    inline = [
      "sudo cp /etc/kubernetes/admin.conf /tmp/kubeconfig",
      "sudo chmod 666 /tmp/kubeconfig"
    ]
  }

  provisioner "local-exec" {
    command = "sftp -o StrictHostKeyChecking=no -i private_key.pem root@${hcloud_server.masters[0].ipv4_address}:/tmp/kubeconfig ./kubeconfig"
  }


}

# add secondary masters
resource "null_resource" "join_other_masters" {
  count      = var.masters_count > 1 ? var.masters_count - 1 : 0
  depends_on = [null_resource.init_first_master]
  connection {
    type        = "ssh"
    user        = "root"
    private_key = tls_private_key.tls.private_key_pem
    host        = hcloud_server.masters[count.index + 1].ipv4_address
  }

  # join cluster as master
  provisioner "remote-exec" {
    inline = [
      "JOIN_CMD=$(ssh -o StrictHostKeyChecking=no root@${hcloud_server.masters[0].ipv4_address} 'kubeadm token create --print-join-command')",
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
  network {
    network_id = hcloud_network_subnet.k8s_subnet.network_id
  }

  connection {
    type        = "ssh"
    user        = "root"
    private_key = tls_private_key.tls.private_key_pem
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
      "hostnamectl set-hostname k8s-worker-${count.index + 1}",
      "echo '127.0.0.1 k8s-worker-${count.index + 1}' >> /etc/hosts"
    ]
  }

  # join cluster as worker
  provisioner "remote-exec" {
    inline = [
      "JOIN_CMD=$(ssh -o StrictHostKeyChecking=no root@${hcloud_server.masters[0].ipv4_address} 'kubeadm token create --print-join-command')",
      "CA_CERT_HASH=$(ssh -o StrictHostKeyChecking=no root@${hcloud_server.masters[0].ipv4_address} 'openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl pkey -pubin -outform der | openssl dgst -sha256 -hex | sed 's/^.* //')",
      "sudo $JOIN_CMD --discovery-token-ca-cert-hash sha256:$CA_CERT_HASH --cri-socket=/run/containerd/containerd.sock"
    ]
  }
}


# CNI installation flannel/cilium
resource "null_resource" "install_cni" {
  count = var.masters_count > 0 ? 1 : 0

  provisioner "remote-exec" {
    inline = [
      "if [ \"${var.cni}\" == \"flannel\" ]; then",
      "  kubectl create ns kube-flannel",
      "  kubectl label --overwrite ns kube-flannel pod-security.kubernetes.io/enforce=privileged",
      "  helm repo add flannel https://flannel-io.github.io/flannel/",
      "  helm install flannel --set podCidr=\"10.244.0.0/16\" --namespace kube-flannel flannel/flannel",
      "elif [ \"${var.cni}\" == \"cilium\" ]; then",
      "  helm repo add cilium https://helm.cilium.io/",
      "  helm install cilium cilium/cilium --namespace kube-system",
      "fi"
    ]
  }

  depends_on = [null_resource.init_first_master]
  connection {
    type        = "ssh"
    user        = "root"
    private_key = tls_private_key.tls.private_key_pem
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
    private_key = tls_private_key.tls.private_key_pem
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

resource "null_resource" "save_private_key" {
  provisioner "local-exec" {
    command = <<-EOT
      echo "${tls_private_key.tls.private_key_pem}" > private_key.pem
    EOT
  }
}