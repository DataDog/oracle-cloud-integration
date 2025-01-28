import io
import os
import json
import logging
import gzip
import requests

logger = logging.getLogger(__name__)

DD_SOURCE = "oci.logs"  # Adding a source default name. The source will be mapped to the log's respective service to be processed by the correct pipeline in Datadog.
DD_SERVICE = "oci"  # Adding a service name.
DD_TIMEOUT = 10 * 60  # Adding a timeout for the Datadog API call.
DD_BATCH_SIZE = 1000  # Adding a batch size for the Datadog API call.
REDACTED_FIELDS = [
    "data.identity.credentials",
    "data.request.headers.Authorization",
    "data.request.headers.authorization",
    "data.request.headers.X-OCI-LB-PrivateAccessMetadata",
    "data.request.headers.opc-principal"
]

def _should_redact_sensitive_data() -> bool:
    return os.environ.get("REDACT_SENSITIVE_DATA", "true").lower() == "true"

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

def _get_oci_source_name(body: dict) -> str:
    """
    Returns the source name for the log entry.
    This function determines if the log is an Audit log, and if not, what source it is coming from .

    Args:
        body (dict): A log entry represented as a dictionary.

    Returns:
        str: The source name for the log entry.
    """
    oracle = body.get("oracle")
    logtype = body.get("type")

    if oracle != None and oracle.get("loggroupid") != None and oracle.get("loggroupid") == "_Audit":
        return "oci.audit"

    if logtype != None and logtype != "":
        # logtype is of format com.oraclecloud.{service}.{resource-type}.{category}
        split_logtype = logtype.split(".")
        if len(split_logtype) >= 3:
            return "oci." + split_logtype[2]

    return DD_SOURCE

def _redact_sensitive_data(body: dict) -> dict:
    """
    Redacts sensitive data from the log entry.
    This function removes the specified fields from the log entry to ensure that sensitive information is not sent to Datadog.
 
    Args:
        body (dict): A log entry represented as a dictionary.

    Returns:
        dict: The log entry with sensitive data redacted.
    """
    def redact_field(obj, field_path):
        keys = field_path.split(".")
        for key in keys[:-1]:
            if key in obj:
                obj = obj[key]
            else:
                return  # Stop if the path does not exist
        # Redact the final key if it exists
        if keys[-1] in obj:
            obj[keys[-1]] = "REDACTED"

    for field_path in REDACTED_FIELDS:
        redact_field(body, field_path)

    return body


def _process_single_log(body: dict) -> dict:
    if _should_redact_sensitive_data():
        body = _redact_sensitive_data(body=body)

    data = body.get("data", {})
    source = body.get("source")
    time = body.get("time")
    logtype = body.get("type")
    oracle = body.get("oracle")
    ddsource = _get_oci_source_name(body)

    payload = {
        "source": source,
        "timestamp": time,
        "data": data,
        "ddsource": ddsource,
        "service": DD_SERVICE,
        "type": logtype,
        "oracle": oracle
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
