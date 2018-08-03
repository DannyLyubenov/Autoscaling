variable "region" {}

variable "cidrs" {
  type = "list"
}

variable "vpc_name" {}

variable "enable" {
  description = "1 = Launch Template \n0 = Launch Configuration"
}
