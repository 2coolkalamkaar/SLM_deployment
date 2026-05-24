# --- Load Balancer ---
output "alb_dns_name" {
  value       = aws_lb.mesh_alb.dns_name
  description = "Public endpoint — run your curl commands against this URL"
}

# --- TypeScript Caller Worker ---
output "ts_worker_instance_id" {
  value       = aws_instance.ts_worker.id
  description = "Instance ID for the TypeScript caller worker (use with SSM)"
}

output "ts_worker_private_ip" {
  value       = aws_instance.ts_worker.private_ip
  description = "Private IP of the TS worker — injected into the Python worker as III_URL"
}

output "ts_worker_public_ip" {
  value       = aws_instance.ts_worker.public_ip
  description = "Public IP of the TS worker (for direct inspection if needed)"
}

# --- Python Inference Worker ---
output "python_worker_instance_id" {
  value       = aws_instance.python_worker.id
  description = "Instance ID for the Python inference worker (use with SSM)"
}

output "python_worker_private_ip" {
  value       = aws_instance.python_worker.private_ip
  description = "Private IP of the Python inference engine"
}

# --- Quick-use SSM commands ---
output "ssm_connect_ts_worker" {
  value       = "aws ssm start-session --target ${aws_instance.ts_worker.id}"
  description = "Copy-paste command to open a shell on the TypeScript worker"
}

output "ssm_connect_python_worker" {
  value       = "aws ssm start-session --target ${aws_instance.python_worker.id}"
  description = "Copy-paste command to open a shell on the Python inference worker"
}

# --- III Mesh URL (as configured on the Python worker) ---
output "python_worker_iii_url" {
  value       = "ws://${aws_instance.ts_worker.private_ip}:49134"
  description = "The III_URL value baked into the Python worker's systemd service"
}
