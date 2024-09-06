import io
import os
import gzip
import json
import logging

import oci
import requests

DD_SOURCE = "Oracle Cloud"  # Adding a source name.
DD_SERVICE = "OCI Logs"  # Adding a service name.
DD_TIMEOUT = 10 * 60  # Adding a timeout for the Datadog API call.

logger = logging.getLogger(__name__)


def handler(ctx, data: io.BytesIO = None) -> None:
    try:
        body = json.loads(data.getvalue())
    except Exception as ex:
        logger.exception(ex)
        return

    data = body.get("data", {})
    additional_details = data.get("additionalDetails", {})

    namespace = additional_details.get("namespace")
    if not namespace:
        logger.error("No namespace provided")
        return

    bucket = additional_details.get("bucketName")
    if not bucket:
        logger.error("No bucket provided")
        return

    resource_name = data.get("resourceName")
    if not resource_name:
        logger.error("No resource provided")
        return

    event_time = body.get("eventTime")
    if not event_time:
        logger.error("No eventTime provided")
        return

    datafile = request_one_object(namespace, bucket, resource_name)
    data = str(datafile, "utf-8")

    # Datadog endpoint URL and token to call the REST interface.
    # These are defined in the func.yaml file.
    try:
        dd_host = os.environ["DATADOG_HOST"]
        dd_token = os.environ["DATADOG_TOKEN"]
        dd_tags = os.environ.get("DATADOG_TAGS", "")
    except KeyError:
        err_msg = "Could not find environment variables, \
                   please ensure DATADOG_HOST and DATADOG_TOKEN \
                   are set as environment variables."
        logger.error(err_msg)

    for lines in data.splitlines():
        logger.info("lines %s", lines)
        payload = {}
        payload.update({"service": DD_SERVICE})
        payload.update({"ddsource": DD_SOURCE})
        payload.update({"ddtags": dd_tags})
        payload.update({"host": resource_name})
        payload.update({"time": event_time})
        payload.update({"event": lines})

    try:
        headers = {"Content-type": "application/json",
                   "Content-encoding": "gzip",
                   "DD-API-KEY": dd_token}
        res = requests.post(dd_host, data=json.dumps(payload), headers=headers,
                            timeout=DD_TIMEOUT)
        logger.info(res.text)
    except Exception:
        logger.exception("Failed to send log to Datadog")


def request_one_object(namespace: str, bucket: str,
                       resource_name: str) -> bytes:
    """
    Calls OCI to request object from Object Storage Client and decompress
    """
    oci_signer = oci.auth.signers.get_resource_principals_signer()
    os_client = oci.object_storage.ObjectStorageClient(config={},
                                                       signer=oci_signer)
    get_obj = os_client.get_object(namespace, bucket, resource_name)
    bytes_read = gzip.decompress(get_obj.data.content)
    return bytes_read
