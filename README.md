# Autoscaling
Demo project which uses Terraform and Ansible to create a webserver

## Terraform 
<pre>Using AWS to creates a Virtual Private Cloud (VPC) with Autoscaling and Application Load Balancer
Upon running "terraform apply" you need to specify 
1 = Launch Template or
0 = Launch Configuration 
in order Terraform to create the appropriate resources
</pre>

## Ansible
<pre>Using a host file which targets servers to install and configure NginX webserver
It also adds a HTML page with Jinja2 templating 
</pre>