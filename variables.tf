variable "region" {}

variable "cidrs" {
  type = "list"
}

variable "vpc_name" {}

variable "enable" {
  description = "1 = Launch Template \n0 = Launch Configuration"
}

variable "min_val" {
  default = "3"
}

variable "max_val" {
  default = "5"
}
