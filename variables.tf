variable "region" {}

variable "pr_cidrs" {
  type = "list"
}

variable "pub_cidrs" {
  type = "list"
}

variable "AMI"{
  default = "ami-3548444c"
}

variable "type"{
  default = "t2.micro"
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
