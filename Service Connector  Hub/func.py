import io
import oci
import re
import os
import json
import sys
import requests
import logging
import time
import gzip
from fdk import response

"""
This function receives the logging json and invokes the Datadog endpoint for ingesting logs. https://docs.cloud.oracle.com/en-us/iaas/Content/Logging/Reference/top_level_logging_format. htm#top_level_logging_format
If this Function is invoked with more than one log the function go over each log and invokes the Datadog endpoint for ingesting one by one.
"""
def handler(ctx, data: io.BytesIO=None):
    try:
        body = json.loads(data.getvalue())
        data = body.get("data", {}) 
        source = body.get("source") 
        time = body.get("time")
        ddsource = "oracle_cloud"
        service = "OCI Logs"

        #get json data, time, and source information
        payload = {}
        payload.update({"source":source}) 
        payload.update({"time": time}) 
        payload.update({"data":data})
        payload.update({"ddsource": ddsource}) 
        payload.update({"service":service})

        #Datadog endpoint URL and token to call the REST interface. These are defined in the func.yaml file. 
        datadoghost = os.environ['DATADOG_HOST']
        datadogtoken = os.environ['DATADOG_TOKEN']

        #Invoke Datadog API with the payload. If the payload contains more than one log this will be ingested as once. headers = {'Content-type': 'application/json', 'DD-API-KEY': datadogtoken}
        x = requests.post(datadoghost, data = json.dumps(payload), headers=headers) 
        logging.getLogger().info(x.text)

        except (Exception, ValueError) as ex: 
            logging.getLogger().info(str(ex)) 
            return