#######################################
#          create AWS project
#######################################
provider "aws" {
  region = "${var.region}"
}

#######################################
#               VPC
#######################################
resource "aws_vpc" "vpc" {
  cidr_block = "192.168.0.0/16"

  tags {
    Name = "${var.vpc_name}"
  }
}

#######################################
#          Internet Gateway
#######################################
resource "aws_internet_gateway" "gw" {
  vpc_id = "${aws_vpc.vpc.id}"

  tags {
    Name = "${var.vpc_name}"
  }
}

#######################################
#          NAT Gateway
#######################################
resource "aws_nat_gateway" "nat" {
  allocation_id = "${aws_eip.eip.id}"
  subnet_id     = "${aws_subnet.public_subnet.0.id}"

  tags {
    Name = "danny_nat"
  }
}

resource "aws_eip" "eip" {
  vpc = true
}

data "aws_availability_zones" "available" {}

#######################################
#                Subnets
#######################################
resource "aws_subnet" "private_subnet" {
  count             = "${length(var.pr_cidrs)}"
  vpc_id            = "${aws_vpc.vpc.id}"
  cidr_block        = "${element(var.pr_cidrs, count.index)}"
  availability_zone = "${element(data.aws_availability_zones.available.names, count.index)}"

  tags {
    Name = "${format("private_%s", "${element(data.aws_availability_zones.available.names, count.index + 1)}" )}"
  }
}

resource "aws_subnet" "public_subnet" {
  count             = "${length(var.pub_cidrs)}"
  vpc_id            = "${aws_vpc.vpc.id}"
  cidr_block        = "${element(var.pub_cidrs, count.index)}"
  availability_zone = "${element(data.aws_availability_zones.available.names, count.index)}"

  tags {
    Name = "${format("public_%s", "${element(data.aws_availability_zones.available.names, count.index + 1)}" )}"
  }
}

#######################################
#               Route Table
#######################################
resource "aws_route_table" "public_table" {
  vpc_id = "${aws_vpc.vpc.id}"

  tags {
    Name = "${format("%s-public", var.vpc_name)}"
  }
}

resource "aws_route" "public_route" {
  route_table_id         = "${aws_route_table.public_table.id}"
  gateway_id             = "${aws_internet_gateway.gw.id}"
  destination_cidr_block = "0.0.0.0/0"
}

#-------------------------------------------------
resource "aws_route_table" "private_table" {
  count  = "${length(var.pr_cidrs)}"
  vpc_id = "${aws_vpc.vpc.id}"

  tags {
    Name = "${format("%s-private", var.vpc_name)}"
  }
}

resource "aws_route" "private_route" {
  count                  = "${length(var.pr_cidrs)}"
  route_table_id         = "${element(aws_route_table.private_table.*.id, count.index)}"
  nat_gateway_id         = "${aws_nat_gateway.nat.id}"
  destination_cidr_block = "0.0.0.0/0"
}

#######################################
#Route table assosiation for each subnet
#######################################
resource "aws_route_table_association" "assosiate_public" {
  count          = "${length(var.pub_cidrs)}"
  subnet_id      = "${element(aws_subnet.public_subnet.*.id,count.index)}"
  route_table_id = "${aws_route_table.public_table.id}"
}

resource "aws_route_table_association" "assosiate_private" {
  count          = "${length(var.pr_cidrs)}"
  subnet_id      = "${element(aws_subnet.private_subnet.*.id,count.index)}"
  route_table_id = "${element(aws_route_table.private_table.*.id, count.index)}"
}

#######################################
#             Security Groups
#######################################
resource "aws_security_group" "allow_all" {
  name        = "allow_all"
  description = "Allow all inbound traffic"
  vpc_id      = "${aws_vpc.vpc.id}"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = "-1"
    to_port     = "-1"
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "allow_all"
  }
}

#######################################
#     Application Load Balancer
#######################################
resource "aws_lb" "balancer" {
  name               = "danny-alb"
  load_balancer_type = "application"
  security_groups    = ["${aws_security_group.allow_all.id}"]
  subnets            = ["${aws_subnet.public_subnet.*.id}"]

  tags {
    Name = "danny_balancer"
  }
}

#######################################
#             Target Group
#######################################
resource "aws_lb_target_group" "target" {
  name     = "danny-target"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "${aws_vpc.vpc.id}"

  health_check {
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 10
    interval            = 30
    matcher             = 200
  }
}

#######################################
#      Target Group Listener
#######################################
resource "aws_lb_listener" "listener" {
  load_balancer_arn = "${aws_lb.balancer.arn}"
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = "${aws_lb_target_group.target.arn}"
    type             = "forward"
  }
}

#######################################
#             Bastian Host
#######################################
resource "aws_instance" "bastion" {
  ami                         = "${var.AMI}"
  instance_type               = "${var.type}"
  associate_public_ip_address = true                                   #auto assign IPv4 address
  vpc_security_group_ids      = ["${aws_security_group.allow_all.id}"]
  key_name                    = "${aws_key_pair.CogKey.key_name}"

  tags {
    Name = "danny_bastian_host"
  }

  # subnet_id = "${element(aws_subnet.subnet.*.id,count.index)}"
  subnet_id = "${aws_subnet.public_subnet.0.id}"

  provisioner "local-exec" {
    command = "./file.py"
  }
}

#######################################
#           Launch Config
#######################################
resource "aws_launch_configuration" "launch_conf" {
  count           = "${var.enable == 0 ? 1 : 0}"
  name_prefix     = "danny_launch_configuration"
  image_id        = "${var.AMI}"
  instance_type   = "${var.type}"
  security_groups = ["${aws_security_group.allow_all.id}"]
  key_name        = "${aws_key_pair.CogKey.key_name}"

}

#######################################
#           Launch Template
#######################################
resource "aws_launch_template" "launch_temp" {
  count         = "${var.enable == 1 ? 1 : 0}"
  name_prefix   = "danny_launch_template"
  image_id      = "${var.AMI}"
  instance_type = "${var.type}"
  key_name      = "${aws_key_pair.CogKey.key_name}"

  tag_specifications {
    resource_type = "instance"

    tags {
      Name = "danny_instance"
    }
  }

  network_interfaces {
    security_groups = ["${aws_security_group.allow_all.id}"]
  }
}

#######################################
#           Auto Scaling
#######################################
resource "aws_autoscaling_group" "scale_template" {
  count               = "${var.enable == 1 ? 1 : 0}"
  name                = "danny_autoscaling_tem"
  min_size            = "${var.min_val}"
  max_size            = "${var.max_val}"
  vpc_zone_identifier = ["${aws_subnet.private_subnet.*.id}"]
  target_group_arns   = ["${aws_lb_target_group.target.arn}"]

  launch_template = {
    id      = "${aws_launch_template.launch_temp.id}"
    version = "$$Latest"
  }

}

resource "aws_autoscaling_group" "scale_config" {
  count               = "${var.enable != 1 ? 1 : 0}"
  name                = "danny_autoscaling_config"
  min_size            = "${var.min_val}"
  max_size            = "${var.max_val}"
  vpc_zone_identifier = ["${aws_subnet.private_subnet.*.id}"]
  target_group_arns   = ["${aws_lb_target_group.target.arn}"]

  launch_configuration = "${aws_launch_configuration.launch_conf.name}"

  tags {
    key                 = "Name"
    value               = "danny_instance"
    propagate_at_launch = true
  }
}

#######################################
#               RSA Key
#######################################
resource "aws_key_pair" "CogKey" {
  key_name   = "Cog-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQD+oRVk9JQSVpA913KHY4LZp788P/9jG/0cGURjAJSKv4jRddmC2Q4W0whpt/yTh0OTKYWwTfdq3zBQqwjWVjzJBviUmL0gsDTUEMTkIA+gLZ/mfiJol5bBVZ7vqDK/UqiroWGjGDUwjK4WQFGaMNl5Agij+guoHimqyfmCw34HXMOcJX08WzqnbDHuDAUvq8j+Le3SFKZg8dnjVUibHYF7MC1/Y2AbCKID5oumWZ+7uS0SFgrBhfAgatIhBT+DKn/goncgWevwPeL13YSnNGn8kw+GG8H3145TfAa7Ixbb1rn350QIRgRUqe717Ja2TVAA3ywAjZXmNKJG2T4tZy08DNsDG9HPXgC2Gt0+9AxzfJ7p1SMAB5pbBoEA1/k3JtWDoyWgYCjmcvLcbswGI8FiORg4CRw7jccRkHDBRc4rY6WMlGpJzlGGiq7JYjgFAjq4GoJ1OxLm0YYvFqzDH2BENJnZFz+ObltSCMHtrV7OHj6wvTXo+Ac+CBxcVw/rYvMdJi4AT8e+qpp7MHPd+nwiCce+6f5tyw4ZgGGTB3TYczkd4MhOQKWqi3a2moCSS+dPkdkjcXMWiQ9enq8yL/bbwGssWq9gwoYrCJnKKD3xVFc6GkFKRQrdzSjyDOiK5cqdkghfFGPm1UJmtT7Bv387twbf21EM1xUcIYnTT4N18w== danny.lyubenov@accessorized.cognitobv.office"
}
