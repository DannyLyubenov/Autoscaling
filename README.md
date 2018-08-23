Objective: Use ansible dynamic inventory to find the hosts inside the autoscaling group to configure nginx

1: Run Terraform Apply to create the 3 private instances and 1 bastion hosts.
2: Go into ansible directory and run ansible-playbook test.yml in order to install NginX onto the 3 boxes 
