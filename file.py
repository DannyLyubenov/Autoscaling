#!/usr/bin/env python
import boto3

def list_instances_by_tag_value(tagkey, tagValue):
    ec2client = boto3.client('ec2')
    response = ec2client.describe_instances(
        Filters=[
            {
                'Name': 'tag:' + tagkey,
                'Values': [tagValue]
            },
            {
                'Name': 'instance-state-name',
                'Values': ['running']
            }
        ]
    )
    instancelist = []
    # print(response)
    for reservation in (response["Reservations"]):
        # print(reservation)
        for instance in reservation["Instances"]:
            instancelist.append(instance["PublicIpAddress"])

    return instancelist


list = list_instances_by_tag_value("Name", "danny_bastian_host")

path = "./ansible/ssh_config"
file = open(path, "w")

file.write("Host 192.168.*.*")
file.write("\n  User centos")
file.write("\n  ProxyJump COG-LABS_BASTION")
file.write("\n")
file.write("\nHost COG-LABS_BASTION")
file.write("\n  HostName " + list[0])
file.write("\n  IdentityFile ~/.ssh/keys/CogKey")
file.write("\n  UserKnownHostsFile /dev/null")
file.write("\n  StrictHostKeyChecking no")

file.close()
