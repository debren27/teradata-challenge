# teradata-challenge

# Usage

Simply execute build-environment.sh. It will create a working directory and create artifacts within that directory as it builds the AWS environment.

# Requirements

  * a linux box to run it on
  * installed packages/commands
    * bash
    * aws cli
    * jq
    * openssl
    * ssh & scp

# Assumptions

  * this is the first basic task in automating this process; more will be done before it's used in production
  * a self-signed cert is OK (non-production)
  * the FQDN is not yet known
  * the instance port (8900) might change, but public ports and protocols will not
  * this will be executed by a person, so some standard output is expected

# Next steps in this project

  * add more error checking
  * add retries to any failed steps
  * add more logging
  * add more debug output for troubleshooting
  * abstract out more settings into arguments or at least variables: public ports, number of instances, etc.
  * add more idempotency, e.g. check for each resource's existence before creating it (already done for VPC and subnet)
  * harden instances for security
