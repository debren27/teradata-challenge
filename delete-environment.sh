#!/bin/sh

# delete-environment.sh
# deletes AWS resources created by build-environment.sh
# must be executed within a working directory
# for testing only; not for production use

if [ -r env.sh ] ; then
  . ./env.sh
else
  echo "ERROR: no env.sh found"
  exit
fi

  aws elb \
    delete-load-balancer \
      --load-balancer-name "${base_name}-elb"

  aws ec2 \
    terminate-instances \
      --instance-ids ${instance_ids}

  aws ec2 \
    disassociate-route-table \
      --association-id "${route_table_association_id}"

#  aws ec2 \
#    delete-route \
#      --route-table-id "${route_table_id}" \
#      --destination-cidr-block "0.0.0.0/0"

  aws ec2 \
    delete-route-table \
      --route-table-id "${route_table_id}"

# need to wait for instances to terminate
for allocation_id in ${allocation_ids} ; do
    aws ec2 \
      release-address \
        --allocation-id "${allocation_id}"
done

  aws ec2 \
    detach-internet-gateway \
      --internet-gateway-id "${internet_gateway_id}" \
      --vpc-id "${vpc_id}"

  aws ec2 \
    delete-internet-gateway \
    --internet-gateway-id "${internet_gateway_id}"

  aws ec2 \
    delete-subnet \
      --subnet-id "${subnet_id}"

  aws ec2 \
    delete-security-group \
      --group-id "${instance_security_group_id}"
  aws ec2 \
    delete-security-group \
      --group-id "${balancer_security_group_id}"

  aws ec2 \
    delete-vpc \
      --vpc-id "${vpc_id}"

#  aws acm \
#    delete-certificate \
#      --certificate-arn "${certificate_arn}"
  aws iam \
    delete-server-certificate \
      --server-certificate-name "${base_name}-cert"

  aws ec2 \
    delete-key-pair \
      --key-name "${base_name}-key"
