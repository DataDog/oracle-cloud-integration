import io
import os
import json
import logging

import requests


def process(body: dict):
    data = body.get("data", {})
    source = body.get("source")
    time = body.get("time")
    dd_source = "oracle_cloud"
    service = "OCI Logs"

    # Get json data, time, and source information
    payload = {}
    payload.update({"source": source})
    payload.update({"time": time})
    payload.update({"data": data})
    payload.update({"ddsource": dd_source})
    payload.update({"service": service})

    # Datadog endpoint URL and token to call the REST interface.
    # These are defined in the func.yaml file.
    try:
        dd_host = os.environ['DATADOG_HOST']
        dd_token = os.environ['DATADOG_TOKEN']
    except KeyError:
        err_msg = "Could not find environment variables, \
                   please ensure DATADOG_HOST and DATADOG_TOKEN \
                   are set as environment variables."
        logging.getLogger().error(err_msg)

    # Invoke Datadog API with the payload.
    # If the payload contains more than one log
    # this will be ingested at once.
    try:
        headers = {'Content-type': 'application/json', 'DD-API-KEY': dd_token}
        x = requests.post(dd_host, data=json.dumps(payload), headers=headers)
        logging.getLogger().info(x.text)
    except (Exception, ValueError) as ex:
        logging.getLogger().error(str(ex))


def handler(ctx, data: io.BytesIO = None):
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
    except (Exception, ValueError) as ex:
        logging.getLogger().error(str(ex))
