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
DD_BATCH_SIZE = 1000  # Adding a batch size for the Datadog API call.


def _should_compress_payload() -> bool:
    return os.environ.get("DD_COMPRESS", "true").lower() == "true"


def _compress_payload(payload: list[dict]):
    try:
        return gzip.compress(json.dumps(payload).encode())
    except Exception as ex:
        logger.error("Could not compress payload to gzip", extra={'Exception': ex})
        return payload


def _process(body: list[dict]) -> None:
    """
    Processes a list of log entries and sends them to the Datadog API.
    This function retrieves the Datadog endpoint URL and token from environment variables,
    processes each log entry in the provided list, compresses the payload, and sends it
    to the Datadog API.
    
    Args:
        body (list[dict]): A list of log entries, where each log entry is represented as a dictionary.
    
    Raises:
        KeyError: If the required environment variables 'DATADOG_HOST' or 'DATADOG_TOKEN' are not set.
        Exception: If there is an error during the API request or payload processing.
    """
    try:
        dd_host = os.environ['DATADOG_HOST']
        dd_token = os.environ['DATADOG_TOKEN']
    except KeyError:
        err_msg = (
            "Could not find environment variables, please ensure DATADOG_HOST and DATADOG_TOKEN "
            "are set as environment variables."
        )
        logger.error(err_msg)
        raise KeyError(err_msg)

    try:
        dd_url = f"https://{dd_host}/api/v2/logs"
        payload = [_process_single_log(b) for b in body]
        headers = {
            "Content-type": "application/json",
            "DD-API-KEY": dd_token
        }
        compressed_payload = payload
        if _should_compress_payload():
            compressed_payload = _compress_payload(payload=payload)

        if isinstance(compressed_payload, bytes):
            headers["Content-Encoding"] = "gzip"
            res = requests.post(dd_url, data=compressed_payload, headers=headers, timeout=DD_TIMEOUT)
        else:
            res = requests.post(dd_url, json=compressed_payload, headers=headers, timeout=DD_TIMEOUT)

        logger.info(res.text)
    except Exception as ex:
        logger.exception(ex)


def _process_single_log(body: dict) -> dict:
    data = body.get("data", {})
    source = body.get("source")
    time = body.get("time")

    payload = {
        "source": source,
        "timestamp": time,
        "data": data,
        "ddsource": DD_SOURCE,
        "service": DD_SERVICE,
    }

    dd_tags = os.environ.get('DATADOG_TAGS', '')
    if dd_tags:
        payload['ddtags'] = dd_tags

    return payload


def handler(ctx, data: io.BytesIO = None) -> None:
    """
    This function receives the logging json and invokes the Datadog endpoint
    for ingesting logs. https://docs.cloud.oracle.com/en-us/iaas/Content/Logging/Reference/top_level_logging_format.htm#top_level_logging_format
    If this Function is invoked with more than one log the function go over
    each log and invokes the Datadog endpoint for ingesting one by one.
    Datadog Logs API: https://docs.datadoghq.com/api/latest/logs/#send-logs
    """
    try:
        body = json.loads(data.getvalue())
        if isinstance(body, list):
            for i in range(0, len(body), DD_BATCH_SIZE):
                batch = body[i:i + DD_BATCH_SIZE]
                _process(batch)
        else:
            _process([body])
    except Exception as ex:
        logger.exception(ex)
