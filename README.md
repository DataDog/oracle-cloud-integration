# Oracle Cloud Integration
Houses code for Datadog OCI integration. Includes code for:
* OCI's log collections pipeline.
* OCI Metric collection setup.



## Deploy to OCI (metrics)

The setup creates an OCI resource manager (ORM) stack which uses terraform to:

* Create resources on OCI to send metrics to Datadog using OCI connector hub
* Create policies in order to allow connector hub to read metrics from different compartments of the tenancy

[![Deploy to Oracle Cloud](https://oci-resourcemanager-plugin.plugins.oci.oraclecloud.com/latest/deploy-to-oracle-cloud.svg)](https://cloud.oracle.com/resourcemanager/stacks/create?zipUrl=https://github.com/Datadog/oracle-cloud-integration/releases/latest/download/datadog-oci-orm.zip)