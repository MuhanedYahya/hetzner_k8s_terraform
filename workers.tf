# worker nodes
resource "hcloud_server" "workers" {
  count       = var.workers_count
  name        = "k8s-worker-${count.index + 1}"
  image       = var.image
  server_type = var.worker_type
  ssh_keys    = [hcloud_ssh_key.hcloud_ssh_public_key.id]
  depends_on  = [null_resource.install_cni]
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
      "/tmp/init.sh"
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
      "$JOIN_CMD",
      "ssh -o StrictHostKeyChecking=no root@${hcloud_server.masters[0].ipv4_address} 'kubectl label nodes k8s-worker-${count.index + 1} node-role.kubernetes.io/worker=worker'"
    ]
  }
}