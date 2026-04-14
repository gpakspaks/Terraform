variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Tag/Name prefix"
  type        = string
  default     = "eks-test"
}

# extra variable: VPC CIDR
variable "vpc_cidr" {
  description = "VPC CIDR (extra variable)"
  type        = string
}

# extra variable: Subnet CIDR (퍼블릭/프라이빗)
variable "subnet_cidrs" {
  description = "Subnet CIDRs (extra variable)"
  type = object({
    public  = list(string)
    private = list(string)
  })

  validation {
    condition     = length(var.subnet_cidrs.public) >= 1 && length(var.subnet_cidrs.private) >= 1
    error_message = "subnet_cidrs.public/private must each have at least 1 CIDR."
  }
}

# Bastion
variable "bastion_instance_type" {
  description = "Bastion EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "bastion_key_name" {
  description = "EC2 key pair name for SSH"
  type        = string
}

variable "bastion_allowed_cidrs" {
  description = "CIDRs allowed to SSH into bastion (e.g., your office IP)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "tag_owner" {
  description = "Default tag value for key 'owner'"
  type        = string
  default     = "yonghyeon.park"
}

variable "aws_profile" {
  description = "AWS CLI profile name to use for this run (e.g., aws-test)"
  type        = string
  default     = null
}