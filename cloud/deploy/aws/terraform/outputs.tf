output "website_url" {
  description = "Il link pubblico per accedere al Frontend del progetto"
  value       = "http://${aws_lb.main.dns_name}"
}

output "master_ip" {
  description = "IP pubblico del Master Node (K8s)"
  value       = aws_instance.k8s_master.public_ip
}

output "worker_1_ip" {
  description = "IP privato del Worker Node 1"
  value       = aws_instance.k8s_worker_1.private_ip
}

output "worker_2_ip" {
  description = "IP privato del Worker Node 2"
  value       = aws_instance.k8s_worker_2.private_ip
}

output "master_private_ip" {
  description = "IP privato del Master Node"
  value       = aws_instance.k8s_master.private_ip
}
