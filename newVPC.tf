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

data "aws_availability_zones" "available" {}

#######################################
#                Subnets
#######################################
resource "aws_subnet" "subnet" {
  count             = "${length(var.cidrs)}"
  vpc_id            = "${aws_vpc.vpc.id}"
  cidr_block        = "${element(var.cidrs, count.index)}"
  availability_zone = "${element(data.aws_availability_zones.available.names, count.index)}"

  tags {
    Name = "${format("AZ_%s", "${element(data.aws_availability_zones.available.names, count.index)}" )}"
  }
}

#
#######################################
#Route table assosiation for each subnet
#######################################
resource "aws_route_table_association" "assosiate" {
  count          = "${length(var.cidrs)}"
  subnet_id      = "${element(aws_subnet.subnet.*.id,count.index)}"
  route_table_id = "${aws_route_table.r.id}"
}

#######################################
#               Route Table
#######################################
resource "aws_route_table" "r" {
  vpc_id = "${aws_vpc.vpc.id}"

  tags {
    Name = "${format("%s-public", var.vpc_name)}"
  }
}

resource "aws_route" "r" {
  route_table_id         = "${aws_route_table.r.id}"
  gateway_id             = "${aws_internet_gateway.gw.id}"
  destination_cidr_block = "0.0.0.0/0"
}

#######################################
#             EC2 Instances
#######################################
resource "aws_instance" "web" {
  count                       = "${length(var.cidrs)}"
  ami                         = "ami-3548444c"
  instance_type               = "t2.micro"
  associate_public_ip_address = true                                   #auto assign IPv4 address
  vpc_security_group_ids      = ["${aws_security_group.allow_all.id}"]
  key_name                    = "${aws_key_pair.CogKey.key_name}"

  tags {
    Name = "${format("instance_%s", "${element(data.aws_availability_zones.available.names, count.index)}")}"
  }

  subnet_id = "${element(aws_subnet.subnet.*.id,count.index)}"
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
  subnets            = ["${aws_subnet.subnet.*.id}"]

  tags {
    Name = "balancer"
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
#      Target Group Attachement
#######################################
resource "aws_lb_target_group_attachment" "attach" {
  count            = "${length(var.cidrs)}"
  target_group_arn = "${aws_lb_target_group.target.arn}"
  target_id        = "${element(aws_instance.web.*.id,count.index)}"
  port             = 80
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = "${aws_lb.balancer.arn}"
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = "arn:aws:acm:eu-west-1:373993042843:certificate/9eedab26-6919-408b-9949-9362d80f75a6"

  default_action {
    target_group_arn = "${aws_lb_target_group.target.arn}"
    type             = "forward"
  }
}

#######################################
#           Launch Config
#######################################
resource "aws_launch_configuration" "launch_conf" {
  count         = "${var.enable == 0 ? 1 : 0}"
  name_prefix   = "danny_launch_configuration"
  image_id      = "ami-3548444c"
  instance_type = "t2.micro"

  lifecycle {
    create_before_destroy = true
  }
}

#######################################
#           Launch Template
#######################################
resource "aws_launch_template" "launch_temp" {
  count         = "${var.enable == 1 ? 1 : 0}"
  name_prefix   = "danny_launch_template"
  image_id      = "ami-3548444c"
  instance_type = "t2.micro"
}

#######################################
#           Auto Scaling
#######################################
resource "aws_autoscaling_group" "scale_template" {
  count               = "${var.enable == 1 ? 1 : 0}"
  name                = "danny_autoscaling"
  min_size            = 1
  max_size            = 5
  vpc_zone_identifier = ["${aws_subnet.subnet.*.id}"]

  launch_template = {
    id      = "${aws_launch_template.launch_temp.id}"
    version = "$$Latest"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "scale_config" {
  count               = "${var.enable != 1 ? 1 : 0}"
  name                = "danny_autoscaling"
  min_size            = 1
  max_size            = 5
  vpc_zone_identifier = ["${aws_subnet.subnet.*.id}"]

  launch_configuration = "${aws_launch_configuration.launch_conf.name}"

  lifecycle {
    create_before_destroy = true
  }
}

#######################################
#               Key
#######################################
resource "aws_key_pair" "CogKey" {
  key_name   = "Cog-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQD+oRVk9JQSVpA913KHY4LZp788P/9jG/0cGURjAJSKv4jRddmC2Q4W0whpt/yTh0OTKYWwTfdq3zBQqwjWVjzJBviUmL0gsDTUEMTkIA+gLZ/mfiJol5bBVZ7vqDK/UqiroWGjGDUwjK4WQFGaMNl5Agij+guoHimqyfmCw34HXMOcJX08WzqnbDHuDAUvq8j+Le3SFKZg8dnjVUibHYF7MC1/Y2AbCKID5oumWZ+7uS0SFgrBhfAgatIhBT+DKn/goncgWevwPeL13YSnNGn8kw+GG8H3145TfAa7Ixbb1rn350QIRgRUqe717Ja2TVAA3ywAjZXmNKJG2T4tZy08DNsDG9HPXgC2Gt0+9AxzfJ7p1SMAB5pbBoEA1/k3JtWDoyWgYCjmcvLcbswGI8FiORg4CRw7jccRkHDBRc4rY6WMlGpJzlGGiq7JYjgFAjq4GoJ1OxLm0YYvFqzDH2BENJnZFz+ObltSCMHtrV7OHj6wvTXo+Ac+CBxcVw/rYvMdJi4AT8e+qpp7MHPd+nwiCce+6f5tyw4ZgGGTB3TYczkd4MhOQKWqi3a2moCSS+dPkdkjcXMWiQ9enq8yL/bbwGssWq9gwoYrCJnKKD3xVFc6GkFKRQrdzSjyDOiK5cqdkghfFGPm1UJmtT7Bv387twbf21EM1xUcIYnTT4N18w== danny.lyubenov@accessorized.cognitobv.office"
}
