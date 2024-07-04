# OUTPUTS

output "master_ips" {
  value       = hcloud_server.master.*.ipv4_address
  description = "IP addresses of the master nodes"
}

output "worker_ips" {
  value       = hcloud_server.worker.*.ipv4_address
  description = "IP addresses of the worker nodes"
}

output "kubeconfig" {
  value       = "ssh -i keys/id_ed25519 -o StrictHostKeyChecking=no root@${hcloud_server.master[0].ipv4_address} 'cat /etc/kubernetes/admin.conf' > ~/.kube/config"
  description = "Get kubeconfig file by running this command"
}

output "cluster_endpoint" {
  value       = hcloud_load_balancer.lb.ipv4
  description = "HA Cluster Endpoint"
}