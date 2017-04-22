#!/bin/bash

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
      --instance-ids ${instance_ids} \
    >/dev/null

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
  # now wait for the instances to start up
  instance_states_nonterm=foo
  checks_done=0
  max_checks=60
  while [ -n "${instance_states_nonterm}" ] ; do
    sleep 1
    aws_response=$(
      aws ec2 \
        describe-instances \
          --instance-ids ${instance_ids}
    )
    instance_states=$(
      echo "${aws_response}" \
        | jq --raw-output '.Reservations[].Instances[].State.Name'
    )
    instance_states_nonterm=$(
      echo "${instance_states}" \
        | grep -v terminated
    )
    let checks_done++
    if [ "${checks_done}" -gt "${max_checks}" ] ; then
      echo "instances took too long to terminate"
    fi
  done

for allocation_id in ${allocation_ids} ; do
    aws ec2 \
      release-address \
        --allocation-id "${allocation_id}"
done

sleep 5

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
