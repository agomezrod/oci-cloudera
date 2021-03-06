# ad-spanning
This is a variation of the N-Node deployment that spans all ADs in a region.  This provides the most highly available solution for running Cloudera EDH on OCI.

## Prerequisites
Installation has a dependency on Terraform being installed and configured for the user tenancy.   As such an `env-vars` file is included with this package that contains all the necessary environment variables.  This file should be updated with the appropriate values prior to installation.  To source this file prior to installation, either reference it in your .rc file for your shell's or run the following:

    source env-vars

## Scaling
Modify the env-vars file prior to deployment and modify the number of workers to scale your cluster dynamically.  You can also scale the number of Utility or Master hosts if you want additional redundancy.  Automated redundancy for Cloudera Manager is NOT currently included in this template.

## Data Tiering
Data Tiering support is now automated.   Go to the top level scripts directory and modify `disk_setup.sh` prior to deployment.   You will find the option:

    enable_data_tiering="0"

Simply change the 0 to a 1 and run your deployment.   Also ensure you have Heterogenous storage configured, by using DenseIO shapes with local NVME and enabling Block Volumes using `block.tf`.  This will allow for a much greater control of HDFS storage density without having to scale the number of Worker nodes in the cluster.  Block Volume size can be adjusted by a variable in `variables.tf`, and this will also scale with the number of Workers in the cluster.

## Password and User Details
Modify the script `startup.sh` and look for the `MAIN CLUSTER CONFIGURATION` section - this is which you can input your contact information, and set up the Cloudera Manager credentials prior to deployment.

## Deployment
Deploy using standard Terraform commands:

    terraform init
    terraform plan
    terraform apply

## Post Deployment
Post deployment is automated using a scripted process that uses the Bash and Cloudera Manager API via Python.  Clusters are preconfigured with tunings based around instance type (in the `cmx.py` script).  Log in to the Bastion host after Terraform completes, then run the following commands to watch installation progress.  The public IP will output as a result of the Terraform completion:

    ssh -i ~/.ssh/id_rsa opc@<public_ip_of_bastion>
    sudo su -
    screen -r

Cluster provisioning can take up to half an hour.  After SCM setup is complete, you can monitor progress  directly using the Cloudera Manager UI.  The URL for this is also output as part of the Terraform provisioning process.

## Security and Post Deployment Auditing
Note that as part of this deployment, ssh keys are used for root level access to provisioned hosts in order to setup software.  The key used is the same as the OPC user which has super-user access to the hosts by default.  If enhanced security is desired, then the following steps should be taken after the Cluster is up and running:

Remove ssh private keys from the Bastion and Utility hosts:

    rm -f /home/opc/.ssh/id_rsa

Replace the authorized_keys file in `/root/.ssh/` on all hosts with the backup copy:

    sudo mv /root/.ssh/authorized_keys.bak /root/.ssh/authorized_keys
