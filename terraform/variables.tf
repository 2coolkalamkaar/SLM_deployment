variable "aws_region" {
  description = "AWS region to deploy all resources in"
  type        = string
  default     = "us-east-1"
}

variable "ts_instance_type" {
  description = "EC2 instance type for the TypeScript caller worker"
  type        = string
  default     = "t3.medium"
}

variable "python_instance_type" {
  description = "EC2 instance type for the Python inference worker"
  type        = string
  default     = "t3.medium"
}

variable "python_volume_size_gb" {
  description = "Root EBS volume size (GB) for the Python worker — needs space for model weights"
  type        = number
  default     = 30
}

variable "swap_size_gb" {
  description = "Swap file size (GB) provisioned on the Python worker to prevent OOM"
  type        = number
  default     = 8
}
