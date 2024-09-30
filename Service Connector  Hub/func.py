import io
import os
import json
import logging
import gzip

import requests

logger = logging.getLogger(__name__)

DD_SOURCE = "oracle_cloud"  # Adding a source name.
DD_SERVICE = "OCI Logs"  # Adding a service name.
DD_TIMEOUT = 10 * 60  # Adding a timeout for the Datadog API call.

def _compress_payload(payload : dict) :
    compressed_payload = payload
    try:
        compressed_payload = gzip.compress(json.dumps(payload).encode())
    except:
        logger.error("Could not compress payload to gzip")
    return compressed_payload


def process(body: dict) -> None:
    data = body.get("data", {})
    source = body.get("source")
    time = body.get("time")

    # Get json data, time, and source information
    payload = {
        "source" : source,
        "timestamp" : time,
        "data" : data,
        "ddsource" : DD_SOURCE,
        "service" : DD_SERVICE,
    }

    # Datadog endpoint URL and token to call the REST interface.
    # These are defined in the func.yaml file.
    dd_tags = None
    try:
        dd_host = os.environ['DATADOG_HOST']
        dd_token = os.environ['DATADOG_TOKEN']
        dd_tags = os.environ.get('DATADOG_TAGS', '')
    except KeyError:
        err_msg = "Could not find environment variables, \
                   please ensure DATADOG_HOST and DATADOG_TOKEN \
                   are set as environment variables."
        logger.error(err_msg)

    if dd_tags:
        payload['ddtags'] = dd_tags

    # Invoke Datadog API with the payload.
    # If the payload contains more than one log
    # this will be ingested at once.
    try:
        headers = {
            "Content-type": "application/json",
            "DD-API-KEY": dd_token
        }
        compressed_payload = _compress_payload(payload=payload)
        if isinstance(compressed_payload, bytes):
            headers["Content-encoding"] = "gzip"
        res = requests.post(dd_host, data=compressed_payload, headers=headers,
                            timeout=DD_TIMEOUT)
        logger.info(res.text)
    except Exception as ex:
        logger.exception(ex)


def handler(ctx, data: io.BytesIO = None) -> None:
    """
    This function receives the logging json and invokes the Datadog endpoint
    for ingesting logs. https://docs.cloud.oracle.com/en-us/iaas/Content/Logging/Reference/top_level_logging_format.htm#top_level_logging_format
    If this Function is invoked with more than one log the function go over
    each log and invokes the Datadog endpoint for ingesting one by one.
    """
    try:
        body = json.loads(data.getvalue())
        if isinstance(body, list):
            # Batch of CloudEvents format
            for b in body:
                process(b)
        else:
            # Single CloudEvent
            process(body)
    except Exception as ex:
        logger.exception(ex)
