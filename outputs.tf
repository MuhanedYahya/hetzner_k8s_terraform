# OUTPUTS

output "master_ips" {
  value       = hcloud_server.masters.*.ipv4_address
  description = "IP addresses of the master nodes"
}

output "worker_ips" {
  value       = hcloud_server.workers.*.ipv4_address
  description = "IP addresses of the worker nodes"
}

output "kubeconfig" {
  value       = "ssh -i keys/id_ed25519 -o StrictHostKeyChecking=no root@${hcloud_server.masters[0].ipv4_address} 'cat /etc/kubernetes/admin.conf' > config"
  description = "Get kubeconfig file by running this command"
}