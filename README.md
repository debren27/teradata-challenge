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
