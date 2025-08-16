variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "key_name" {
  description = "Name of the AWS key pair"
  type        = string
}

variable "tags" {
  description = "Tags to be applied to all resources"
  type        = map(string)
  default     = {}
}