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


def handler(ctx, data: io.BytesIO=None):
    try:
        body = json.loads(data.getvalue())
        data = body.get("data", {})
        additional_details = data.get("additionalDetails", {})
        namespace = additional_details.get("namespace")
        bucket = additional_details.get("bucketName")
        obj = data.get("resourceName")
        eventtime = body.get("eventTime")

        source = "Oracle Cloud" #adding a source name.
        service = "OCI Logs" #adding a service name.

        datafile = request_one_object(namespace, bucket, obj)
        data = str(datafile,'utf-8')

        datadoghost = os.environ['DATADOG_HOST']
        datadogtoken = os.environ['DATADOG_TOKEN']

        for lines in data.splitlines():
            logging.getLogger().info("lines " + lines)
            payload = {}
            payload.update({"host":obj})
            payload.update({"time": eventtime})

            payload.update({"ddsource":source}) 
            payload.update({"service":service})

            payload.update({"event":lines})

            
 
        headers = {'Content-type': 'application/json', 'DD-API-KEY': datadogtoken}
        x = requests.post(datadoghost, data = json.dumps(payload), headers=headers)
        logging.getLogger().info(x.text)
        print(x.text)

    except (Exception, ValueError) as ex:
#        print(str(ex))
        logging.getLogger().info(str(ex))
        return


def request_one_object(namespace, bucket, obj):
    assert bucket and obj
    signer = oci.auth.signers.get_resource_principals_signer()
    object_storage_client = oci.object_storage.ObjectStorageClient(config={}, signer=signer)
    namespace = namespace
    bucket_name = bucket
    object_name = obj
    get_obj = object_storage_client.get_object(namespace, bucket_name, object_name)
    bytes_read = gzip.decompress(get_obj.data.content)
    return bytes_read
