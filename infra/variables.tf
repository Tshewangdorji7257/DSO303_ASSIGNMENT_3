variable "region" {
  type    = string
  default = "ap-southeast-1"
}
variable "project" {
  type    = string
  default = "exam-a3"
}
variable "image_tag" {
  type    = string
  default = "latest"
}
variable "alert_email" {
  type        = string
  description = "Receives CloudWatch alarm emails"
}
variable "notify_email" {
  type        = string
  description = "SES sender and tutor recipient (must be verified in SES)"
}
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}
variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}
variable "api_min_tasks" {
  type    = number
  default = 2 # one per AZ
}
variable "api_max_tasks" {
  type    = number
  default = 20
}

variable "pg_pool_max" {
  type        = number
  default     = 10
  description = "Max PostgreSQL connections per API task (pg Pool max)"
}

variable "waf_rate_limit" {
  type        = number
  default     = 2000
  description = "WAF rate-based rule: requests per 5 minutes per IP"
}
