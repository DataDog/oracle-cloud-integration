# Oracle Cloud Integration

Houses code for Datadog OCI integration.

## Datadog Integration Setup

The primary integration setup is located in the `datadog-integration` folder. This unified stack handles both:

- OCI log collection
- OCI metrics collection

The setup creates an OCI Resource Manager (ORM) stack which uses Terraform to:

- Create resources on OCI to send logs and metrics to Datadog using OCI Service Connector Hub
- Create policies to allow Service Connector Hub to read logs and metrics from different compartments of the tenancy
- Deploy serverless functions for log and metric forwarding to Datadog

**Important:** The stack must be deployed in the **home region** of your OCI tenancy.

[![Deploy to Oracle Cloud](https://oci-resourcemanager-plugin.plugins.oci.oraclecloud.com/latest/deploy-to-oracle-cloud.svg)](https://cloud.oracle.com/resourcemanager/stacks/create?zipUrl=https://github.com/Datadog/oracle-cloud-integration/releases/latest/download/datadog-integration.zip)
