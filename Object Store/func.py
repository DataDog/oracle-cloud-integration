import io
import os
import gzip
import json
import logging

import oci
import requests


def handler(ctx, data: io.BytesIO = None):
    try:
        body = json.loads(data.getvalue())
    except (Exception, ValueError) as ex:
        logging.getLogger().info(str(ex))
        return

    data = body.get("data", {})
    additional_details = data.get("additionalDetails", {})

    namespace = additional_details.get("namespace")
    if not namespace:
        logging.getLogger().error("No namespace provided")
        return
        
    bucket = additional_details.get("bucketName")
    if not bucket:
        logging.getLogger().error("No bucket provided")
        return

    resource_name = data.get("resourceName")
    if not resource_name:
        logging.getLogger().error("No obj provided")
        return

    event_time = body.get("eventTime")

    source = "Oracle Cloud"  # Adding a source name.
    service = "OCI Logs"     # Adding a service name.

    datafile = request_one_object(namespace, bucket, resource_name)
    data = str(datafile, 'utf-8')

    dd_host = os.environ['DATADOG_HOST']
    dd_token = os.environ['DATADOG_TOKEN']

    for lines in data.splitlines():
        logging.getLogger().info("lines %s", lines)
        payload = {}
        payload.update({"host": resource_name})
        payload.update({"time": event_time})

        payload.update({"ddsource": source})
        payload.update({"service": service})

        payload.update({"event": lines})

    headers = {'Content-type': 'application/json', 'DD-API-KEY': dd_token}
    req = requests.post(dd_host, data=json.dumps(payload), headers=headers)
    logging.getLogger().info(req.text)


def request_one_object(namespace: str, bucket: str, resource_name: str):
    """
    Calls OCI to request object from Object Storage Client and decompress
    """
    oci_signer = oci.auth.signers.get_resource_principals_signer()
    os_client = oci.object_storage.ObjectStorageClient(config={},
                                                       signer=oci_signer)
    get_obj = os_client.get_object(namespace, bucket, resource_name)
    bytes_read = gzip.decompress(get_obj.data.content)
    return bytes_read
