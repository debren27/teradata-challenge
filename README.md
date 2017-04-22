# teradata-challenge

# Usage

Simply execute teradata-challenge/build-environment.sh. It will create a working directory and create artifacts within that directory as it builds the AWS environment. Since it does create a subdirectory, it's preferable to execute it from outside the teradata-challenge directory.

# Requirements

  * a linux box to run it on
  * installed packages/commands
    * git
    * bash
    * aws cli
    * jq
    * openssl
    * ssh & scp

# Assumptions

  * this is the first basic task (POC/spike) in automating this process; more will be done before it's used in production
  * a self-signed cert is acceptable (non-production)
  * the FQDN is not yet known
  * settings such as ports, number of instances, etc. are not likely to change
  * this will be executed by a person, so some standard output is expected/desired
  * no need for multi-AZ; redundancy will be handled elsewhere
  * because ACM permissions have not been granted, IAM is preferred for certificate management

# Next steps in this project

  * add more error checking
  * add retries to any failed steps
  * add more logging
  * add more debug output for troubleshooting
  * abstract out more settings into arguments or at least variables: public ports, number of instances, etc.
  * add more idempotency, e.g. check for each resource's existence before creating it (already done for VPC and subnet)
  * harden instances for security
  * if desired, refactor in Python or other tool

# Notes

  * I chose bash because it's the most portable, and fastest to get started
  * For more flexibility and resiliency, this should be written in a real language or deployment tool
  * If speed is a factor, bash is slow, especially with all the awscli (Python) calls; but other pieces such as API calls probably slow this down more

# Sample output

```
donovan@ubuntu:~$ time teradata-challenge/build-environment.sh
Working inside directory ./teradata-meyers.dK6
Wrote new SSL key to teradata-meyers.ADM3.com-key.pem and new SSL cert to teradata-meyers.ADM3.com-cert.pem
Imported certificate to AWS IAM with ARN arn:aws:iam::571541063207:server-certificate/teradata-meyers-cert
Found/created VPC with ID vpc-c77b50a0 using CIDR block 10.10.0.0/16
Found/created subnet with ID subnet-953aa4dc in VPC vpc-c77b50a0
Created internet gateway with ID igw-2d49a74a
Attached internet gateway igw-2d49a74a to VPC vpc-c77b50a0
Created balancer security group named teradata-meyers-balancer-sg with ID sg-5e07b525

An error occurred (CertificateNotFound) when calling the CreateLoadBalancer operation: Server Certificate not found for the key: arn:aws:iam::571541063207:server-certificate/teradata-meyers-cert
retrying...
Created load balancer named teradata-meyers-elb with listeners on ports 80 and 443; DNS is teradata-meyers-elb-25915425.us-west-2.elb.amazonaws.com
Created keypair named teradata-meyers-key and wrote to teradata-meyers-key.pem
Created instance security group named teradata-meyers-instance-sg with ID sg-f91daf82
Created instances with IDs i-046ac85130aedfd6d i-0e93a5f9fa07979b9 i-0a32b7d513fb32dcf
Waiting for instances to become available.........
Created route table with ID rtb-5ac9113c
Created outgoing route in route table rtb-5ac9113c through gateway igw-2d49a74a
Associated route table rtb-5ac9113c to subnet subnet-953aa4dc with association ID rtbassoc-f8d70081
Allocated and assigned public IP addresses  35.166.84.170 54.71.198.68 52.39.21.170 with allocation IDs  eipalloc-31f76d0b eipalloc-f6f76dcc eipalloc-a1f46e9b
Authorized CIDRs 70.95.202.114/32 141.206.246.10/32 to ssh port 22 in instance security group
Wrote install scripts apache-install-config.sh and nginx-install-config.sh
apache-install-config.sh                      100%  666     0.7KB/s   00:00
Installed apache on 35.166.84.170; wrote log to apache_install_on_35.166.84.170.log
apache-install-config.sh                      100%  666     0.7KB/s   00:00
Installed apache on 54.71.198.68; wrote log to apache_install_on_54.71.198.68.log
nginx-install-config.sh                       100%  551     0.5KB/s   00:00
Installed nginx on 52.39.21.170; wrote log to nginx_install_on_52.39.21.170.log
Registered instances i-046ac85130aedfd6d i-0e93a5f9fa07979b9 i-0a32b7d513fb32dcf with balancer teradata-meyers-elb
Authorized public to reach ports 80 and 443 on balancer
Authorized balancer to reach internal web port 8900

You should now be able to connect to:
http://teradata-meyers-elb-25915425.us-west-2.elb.amazonaws.com
https://teradata-meyers-elb-25915425.us-west-2.elb.amazonaws.com

real    1m49.444s
user    0m15.960s
sys     0m1.356s
```
