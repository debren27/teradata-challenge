#!/bin/bash

http_port=80
https_port=443
base_name='teradata-meyers'
instance_port=8900
vpc_cidr_block='10.10.0.0/16'
instance_image_id='ami-5e63d13e'
instance_type='t2.micro'
ssh_source_cidrs='70.95.202.114/32 141.206.246.10/32'
apex_domain='ADM3.com'

website_fqdn="${base_name}.${apex_domain}"
ssl_key_file="${website_fqdn}-key.pem"
ssl_cert_file="${website_fqdn}-cert.pem"
ssh_key_file="${base_name}-key.pem"

# find and verify required non-standard commands

jq_bin=$( which jq 2>/dev/null )
aws_bin=$( which aws 2>/dev/null )
openssl_bin=$( which openssl 2>/dev/null )
ssh_bin=$( which ssh 2>/dev/null )
scp_bin=$( which scp 2>/dev/null )

if [ -z "${jq_bin}" ] ; then echo "ERROR: jq must be installed and on PATH; exiting" ; exit 1 ; fi
if [ -z "${aws_bin}" ] ; then echo "ERROR: aws (awscli) must be installed and on PATH; exiting" ; exit 1 ; fi
if [ -z "${openssl_bin}" ] ; then echo "ERROR: openssl must be installed and on PATH; exiting" ; exit 1 ; fi
if [ -z "${ssh_bin}" ] ; then echo "ERROR: ssh must be installed and on PATH; exiting" ; exit 1 ; fi
if [ -z "${scp_bin}" ] ; then echo "ERROR: scp must be installed and on PATH; exiting" ; exit 1 ; fi

aws_bin="${aws_bin} --output json" 

## FUNCTIONS

error_exit () {
  echo "ERROR: ${1}; aborting"
  exit 1
}

make_working_directory () {

  # first check if we're already in one of our working dirs
  # if so, read in the environment variable file
  current_dir_path=$( pwd )
  current_dir_name=$( basename "${current_dir_path}" )

  if [[ "${current_dir_name}" =~ ^${base_name} ]] ; then
    working_dir="${current_dir_path}"
  else
    # if we're not already in one of our working dirs, create one and move into it
    working_dir=$(
      mktemp -d -p . ${base_name}.XXX
    )
  fi

  cd "${working_dir}"
  echo "Working inside directory ${working_dir}"

  if [ -r env.sh ] ; then
    . env.sh
  else
    # as we go, we'll write our variables to an environment file so we can source it and resume
    cat <<EOF >env.sh
http_port='${http_port}'
https_port='${https_port}'
base_name='${base_name}'
instance_port='${instance_port}'
vpc_cidr_block='${vpc_cidr_block}'
instance_image_id='${instance_image_id}'
instance_type='${instance_type}'
ssh_source_cidrs='${ssh_source_cidrs}'
apex_domain='${apex_domain}'
website_fqdn='${website_fqdn}'
ssl_key_file='${ssl_key_file}'
ssl_cert_file='${ssl_cert_file}'
ssh_key_file='${ssh_key_file}'
EOF

  fi
}

test_keys () {

  aws_response=$(
    ${aws_bin} ec2 \
      describe-instances \
      2>&1 1>/dev/null \
      | grep -v '^$'
  )

  if [ -n "${aws_response}" ] ; then
    error_exit "key check failed; please run \"aws configure\"; error was \"${aws_response}\""
  fi

}

create_ssl_cert () {

  ${openssl_bin} req \
    -x509 \
    -nodes \
    -newkey rsa:2048 -keyout "${ssl_key_file}" \
    -out "${ssl_cert_file}" \
    -days 3650 \
    -subj "/C=US/ST=California/L=San Diego/O=Teradata/OU=Meyers/CN=${website_fqdn}" \
    >/dev/null

  if [ $? -ne 0 ] ; then
    error_exit "SSL Certificate creation failed"
  else
    echo "Wrote new key to ${ssl_key_file} and new cert to ${ssl_cert_file}"
  fi


}

import_certificate () {

## ACM version (instead of IAM)
## if using, make sure to update create_balancer to use arn instead of id
#  aws_response=$(
#    ${aws_bin} acm \
#      import-certificate \
#        --certificate "$( cat ${ssl_cert_file} )" \
#        --private-key "$( cat ${ssl_key_file} )"
#  )
#  certificate_arn=$(
#    echo "${aws_response}" \
#      | ${jq_bin} --raw-output '.CertificateArn'
#  )
#  echo "Imported cert to AWS ACM with ARN ${certificate_arn}"
#  echo "certificate_arn='${certificate_arn}'" >> env.sh

  aws_response=$(
    ${aws_bin} iam \
      upload-server-certificate \
        --server-certificate-name "${base_name}-cert" \
        --certificate-body "$( cat ${ssl_cert_file} )" \
        --private-key "$( cat ${ssl_key_file} )"
)
#  certificate_id=$(
#    echo "${aws_response}" \
#      | ${jq_bin} --raw-output '.ServerCertificateMetadata.ServerCertificateId'
#  )
  certificate_arn=$(
    echo "${aws_response}" \
      | ${jq_bin} --raw-output '.ServerCertificateMetadata.Arn'
  )

  if [ -n "${certificate_arn}" ] ; then
    echo "Imported certificate to AWS IAM with ARN ${certificate_arn}"
    echo "certificate_arn='${certificate_arn}'" >> env.sh
  else
    error_exit "failed to import certificate"
  fi

}

create_vpc () {

  # first check to see if it exists
  aws_response=$(
    ${aws_bin} ec2 \
      describe-vpcs \
        --filters "Name=cidr,Values=${vpc_cidr_block}"
  )
  vpc_id=$(
    echo "${aws_response}" \
      | ${jq_bin} --raw-output '.Vpcs[0].VpcId'
  )

  if [ -n "${vpc_id}" -a "${vpc_id}" != 'null' ] ; then
    echo "Found existing VPC with CIDR block ${vpc_cidr_block} with ID ${vpc_id}"
    echo "vpc_id='${vpc_id}'" >> env.sh
    return
  fi

  # if it doesn't exist, created it
  aws_response=$(
    ${aws_bin} ec2 \
      create-vpc \
        --cidr-block "${vpc_cidr_block}"
  )
  vpc_id=$(
    echo "${aws_response}" \
      | ${jq_bin} --raw-output '.Vpc.VpcId'
  )

  if [ -n "${vpc_id}" ] ; then
    echo "Found/created VPC with ID ${vpc_id} using CIDR block ${vpc_cidr_block}"
    echo "vpc_id='${vpc_id}'" >> env.sh
  else
    error_exit "failed to create VPC"
  fi

}

create_subnet () {

  # first check to see if it exists
  aws_response=$(
    ${aws_bin} ec2 \
      describe-subnets \
        --filters "Name=vpc-id,Values=${vpc_id},Name=cidrBlock,Values=${vpc_cidr_block}"
  )
  subnet_id=$(
    echo "${aws_response}" \
      | ${jq_bin} --raw-output '.Subnets[0].SubnetId'
  )

  if [ -n "${subnet_id}" -a "${subnet_id}" != 'null' ] ; then
    echo "Found existing subnet in VPC ${vpc_id} with CIDR block ${vpc_cidr_block} with ID ${subnet_id}"
    echo "subnet_id='${subnet_id}'" >> env.sh
    return
  fi

  # if it doesn't exist, created it
  aws_response=$(
    ${aws_bin} ec2 \
      create-subnet \
        --vpc-id "${vpc_id}" \
        --cidr-block "${vpc_cidr_block}"
  )
  subnet_id=$(
    echo "${aws_response}" \
      | ${jq_bin} --raw-output '.Subnet.SubnetId'
  )

  if [ -n "${subnet_id}" ] ; then
    echo "Found/created subnet with ID ${subnet_id} in VPC ${vpc_id}"
    echo "subnet_id='${subnet_id}'" >> env.sh
  else
    error_exit "failed to create subnet"
  fi
}

create_internet_gateway () {

  aws_response=$(
    ${aws_bin} ec2 \
      create-internet-gateway \
  )
  internet_gateway_id=$(
    echo "${aws_response}" \
      | ${jq_bin} --raw-output '.InternetGateway.InternetGatewayId'
  )

  if [ -n "${internet_gateway_id}" ] ; then
    echo "Created internet gateway with ID ${internet_gateway_id}"
    echo "internet_gateway_id='${internet_gateway_id}'" >> env.sh
  else
    error_exit "failed to create internet gateway"
  fi
}

attach_internet_gateway () {

  aws_response=$(
    ${aws_bin} ec2 \
      attach-internet-gateway \
        --internet-gateway-id "${internet_gateway_id}" \
        --vpc-id "${vpc_id}"
  )
  # no output on success

  echo "Attached internet gateway ${internet_gateway_id} to VPC ${vpc_id}"

}

create_balancer_security_group () {

  aws_response=$(
    ${aws_bin} ec2 \
      create-security-group \
        --group-name "${base_name}-balancer-sg" \
        --description "Security group for balancer created by Donovan Meyers solution of the Teradata Code Challenge" \
        --vpc-id "${vpc_id}"
  )
  balancer_security_group_id=$(
    echo "${aws_response}" \
      | ${jq_bin} --raw-output '.GroupId'
  )

  if [ -n "${balancer_security_group_id}" ] ; then
    echo "Created balancer security group named ${base_name}-balancer-sg with ID ${balancer_security_group_id}"
    echo "balancer_security_group_id='${balancer_security_group_id}'" >> env.sh
  else
    error_exit "failed to create balancer security group"
  fi
}

create_balancer () {

  aws_response=$(
    ${aws_bin} elb \
      create-load-balancer \
        --load-balancer-name "${base_name}-elb" \
        --listeners \
          "Protocol=http,LoadBalancerPort=${http_port},InstanceProtocol=http,InstancePort=${instance_port}" \
          "Protocol=https,LoadBalancerPort=${https_port},InstanceProtocol=http,InstancePort=${instance_port},SSLCertificateId=${certificate_arn}" \
        --subnets "${subnet_id}" \
        --security-groups "${balancer_security_group_id}"
  )
  elb_dns_name=$(
    echo "${aws_response}" \
      | ${jq_bin} --raw-output '.DNSName'
  )

  if [ -n "${elb_dns_name}" ] ; then
    echo "Created load balancer named ${base_name}-elb with listeners on ports ${http_port} and ${https_port}; DNS is ${elb_dns_name}"
    echo "elb_dns_name='${elb_dns_name}'" >> env.sh
  else
    error_exit "failed to create balancer"
  fi
}

create_keypair () {

  aws_response=$(
    ${aws_bin} ec2 \
      create-key-pair \
        --key-name "${base_name}-key"
  )
  key_material=$(
    echo "${aws_response}" \
      | ${jq_bin} --raw-output '.KeyMaterial'
  )
  echo -e "${key_material}" \
    > "${ssh_key_file}"
  chmod 600 "${ssh_key_file}"

  echo "Created keypair named ${base_name}-key and wrote to ${ssh_key_file}"

}

create_instance_security_group () {

  aws_response=$(
    ${aws_bin} ec2 \
      create-security-group \
        --group-name "${base_name}-instance-sg" \
        --description "Security group for instances created by Donovan Meyers solution of the Teradata Code Challenge" \
        --vpc-id "${vpc_id}"
  )
  instance_security_group_id=$(
    echo "${aws_response}" \
      | ${jq_bin} --raw-output '.GroupId'
  )

  echo "Created instance security group named ${base_name}-instance-sg with ID ${instance_security_group_id}"

  echo "instance_security_group_id='${instance_security_group_id}'" >> env.sh
}

create_instances () {

  aws_response=$(
    ${aws_bin} ec2 \
      run-instances \
        --instance-type "${instance_type}" \
        --image-id "${instance_image_id}" \
        --subnet-id "${subnet_id}" \
        --security-group-ids "${instance_security_group_id}" \
        --key-name "${base_name}-key" \
        --count 3
  )
  instance_ids=$(
    echo "${aws_response}" \
      | ${jq_bin} --raw-output '.Instances[].InstanceId'
  )

  echo "instance_ids='${instance_ids}'" >> env.sh

  echo -n "Waiting for instances to become available..."

  # now wait for the instances to start up
  instance_states_nonrunning=foo
  checks_done=0
  max_checks=60
  while [ -n "${instance_states_nonrunning}" ] ; do
    sleep 1
    aws_response=$(
      ${aws_bin} ec2 \
        describe-instances \
          --instance-ids ${instance_ids}
    )
    instance_states=$(
      echo "${aws_response}" \
        | ${jq_bin} --raw-output '.Reservations[].Instances[].State.Name'
    )
    instance_states_nonrunning=$(
      echo "${instance_states}" \
        | grep -v running
    )
    let checks_done++
    if [ "${checks_done}" -gt "${max_checks}" ] ; then
      error_exit "instances took too long to become available"
    fi
    echo -n .
  done
  echo

  echo "Created instances with IDs "${instance_ids}
}

create_route_table () {

  aws_response=$(
    ${aws_bin} ec2 \
      create-route-table \
        --vpc-id "${vpc_id}" \
  )
  route_table_id=$(
    echo "${aws_response}" \
      | ${jq_bin} --raw-output '.RouteTable.RouteTableId'
  )

  echo "Created route table with ID ${route_table_id}"

  echo "route_table_id='${route_table_id}'" >> env.sh
}

create_route () {

  aws_response=$(
    ${aws_bin} ec2 \
      create-route \
        --route-table-id "${route_table_id}" \
        --destination-cidr-block 0.0.0.0/0 \
        --gateway-id "${internet_gateway_id}"
  )
  status=$(
    echo "${aws_response}" \
      | ${jq_bin} --raw-output '.Return'
  )
  if [ "${status}" != 'true' ] ; then
    error_exit "failed to create route"
  fi

  echo "Created outgoing route in route table ${route_table_id} through gateway ${internet_gateway_id}"

}

associate_route_table () {

  aws_response=$(
    ${aws_bin} ec2 \
      associate-route-table \
        --subnet-id "${subnet_id}" \
        --route-table-id "${route_table_id}"
  )
  route_table_association_id=$(
    echo "${aws_response}" \
      | ${jq_bin} --raw-output '.AssociationId'
  )

  echo "Associated route table ${route_table_id} to subnet ${subnet_id} with association ID ${route_table_association_id}"

  echo "route_table_association_id='${route_table_association_id}'" >> env.sh
}

authorize_ssh () {

  for cidr in ${ssh_source_cidrs} ; do
    aws_response=$(
      ${aws_bin} ec2 \
        authorize-security-group-ingress \
          --group-id "${instance_security_group_id}" \
          --protocol tcp \
          --port 22 \
          --cidr "${cidr}"
    )
    # empty response on success; need a different error check (stderr)
  done

  echo "Authorized CIDRs "${ssh_source_cidrs}" to ssh port 22 in instance security group ${security_group_id}"

}

assign_public_ips () {

  unset public_ips
  unset allocation_ids
  for instance_id in ${instance_ids} ; do
    aws_response=$(
      ${aws_bin} ec2 \
        allocate-address \
          --domain vpc
    )
    public_ip=$(
      echo "${aws_response}" \
        | ${jq_bin} --raw-output '.PublicIp'
    )
    public_ips="${public_ips} ${public_ip}"
    allocation_id=$(
      echo "${aws_response}" \
        | ${jq_bin} --raw-output '.AllocationId'
    )
    allocation_ids="${allocation_ids} ${allocation_id}"
    aws_response=$(
      ${aws_bin} ec2 \
        associate-address \
          --instance-id "${instance_id}" \
          --allocation-id "${allocation_id}"
    )
  done

  echo "Allocated and assigned public IP addresses "${public_ips}" with allocation IDs "${allocation_ids}

  echo "public_ips='${public_ips}'" >> env.sh
  echo "allocation_ids='${allocation_ids}'" >> env.sh
}

write_install_scripts () {

  cat <<EOF >apache-install-config.sh
#!/bin/bash
apt-get -y update
apt-get -y install apache2
sed -i 's/80/${instance_port}/' /etc/apache2/sites-available/000-default.conf
sed -i 's/Listen 80/Listen ${instance_port}/' /etc/apache2/ports.conf
mkdir -p /var/log/tdcustom/accesslogs
sed -i 's#^export APACHE_LOG_DIR=.*#export APACHE_LOG_DIR=/var/log/tdcustom/accesslogs#' /etc/apache2/envvars
sed -i 's#/var/log/apache2#/var/log/tdcustom/accesslogs#' /etc/logrotate.d/apache2
mv /var/www/html/index.html /var/www/html/index.html.orig
echo '<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><title>Meyers</title></head><body>Hello World! Donovan was here.</body></html>' > /var/www/html/index.html
service apache2 restart
EOF

  cat <<EOF >nginx-install-config.sh
#!/bin/bash
apt-get -y update
apt-get -y install nginx
sed -i \
  -e 's/listen 80 default_server/listen ${instance_port} default_server/' \
  -e 's/listen \[::\]:80 default_server/listen [::]:${instance_port} default_server/' \
  /etc/nginx/sites-enabled/default
mkdir -p /var/log/tdcustom/accesslogs
sed -i 's#/var/log/nginx#/var/log/tdcustom/accesslogs#' /etc/nginx/nginx.conf
echo '<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><title>Meyers</title></head><body>Hello World! Donovan was here.</body></html>' > /usr/share/nginx/html/index.html
service nginx restart
EOF

  chmod 750 apache-install-config.sh nginx-install-config.sh

  echo "Wrote install scripts apache-install-config.sh and nginx-install-config.sh"

}

install_software () {

  # wait for ssh to open the port
  attempts_done=0
  max_attempts=10
  while [ "${attempts_done}" -lt "${max_attempts}" ] ; do
    let attempts_done++
    connects_failed=0
    for public_ip in ${public_ips} ; do
      ${ssh_bin} -o StrictHostKeyChecking=no \
        -i "${ssh_key_file}" \
        -l ubuntu \
        ${public_ip} \
        hostname
      if [ $? != 0 ] ; then
        let connects_failed++
      fi
    done
    if [ "${connects_failed}" = 0 ] ; then
      break
    fi
  done

  instance_index=0
  for public_ip in ${public_ips} ; do
    let instance_index++
    if [ "${instance_index}" -le 2 ] ; then
      software='apache'
    else
      software='nginx'
    fi
    script="${software}-install-config.sh"
    ${scp_bin} -p \
      -i "${ssh_key_file}" \
      "${script}" ubuntu@${public_ip}:
    ${ssh_bin} \
      -i "${ssh_key_file}" \
      -l ubuntu \
      ${public_ip} \
        sudo "./${script}" \
          > "${software}_install_on_${public_ip}.log" 2>&1
    echo "Installed ${software} on ${public_ip}; wrote log to ${software}_install_on_${public_ip}.log"
  done

}

register_instances_with_balancer () {

  aws_response=$(
    ${aws_bin} elb \
      register-instances-with-load-balancer \
        --load-balancer-name "${base_name}-elb" \
        --instances ${instance_ids}
  )

  echo "Registered instances "${instance_ids}" with balancer ${base_name}-elb"

}

authorize_balancer_to_instances () {

  aws_response=$(
    ${aws_bin} ec2 \
      authorize-security-group-ingress \
        --group-id "${instance_security_group_id}" \
        --protocol tcp \
        --port ${instance_port} \
        --source-group "${balancer_security_group_id}"
  )
  # no response on success; error check stderr

  echo "Authorized balancer to reach internal web port ${instance_port}"

}

authorize_public_web () {

  for public_port in ${http_port} ${https_port} ; do
    aws_response=$(
      ${aws_bin} ec2 \
        authorize-security-group-ingress \
          --group-id "${balancer_security_group_id}" \
          --protocol tcp \
          --port "${public_port}" \
          --cidr 0.0.0.0/0
    )
  done

  echo "Authorized public to reach ports ${http_port} and ${https_port} on balancer"
}

## MAIN

# create and move into a working directory, if we're not already
make_working_directory

# before we try anything, make sure our keys are good
test_keys

# generate a cert for HTTPS, and import it into Amazon's ACM for use with balancer
create_ssl_cert
import_certificate

# configure the basic networking, including gateway for bidirectional internet access
create_vpc
create_subnet
create_internet_gateway
attach_internet_gateway

# create the ELB balancer with its own security group
create_balancer_security_group
sleep 60
create_balancer

# create the instances with their own keypair and security group
create_keypair
create_instance_security_group
create_instances

# configure the routing so the instances can reach the internet
create_route_table
create_route
associate_route_table

# give instances public IP addresses and allow Teradata and Donovan to reach them
assign_public_ips
authorize_ssh

# install the webserver software on the instances
write_install_scripts
install_software

# configure the path from public to balancer to instances
register_instances_with_balancer
authorize_public_web
authorize_balancer_to_instances

echo
echo "You should now be able to connect to:"
echo "http://${elb_dns_name}"
echo "https://${elb_dns_name}"

exit

