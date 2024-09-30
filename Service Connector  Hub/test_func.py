import os

from io import BytesIO
from func import handler
from unittest import TestCase, mock


def to_BytesIO(str):
    """ Helper function to turn string test data into expected BytesIO asci encoded bytes """
    return BytesIO(bytes(str, 'ascii'))


class TestLogForwarderFunction(TestCase):
    """ Test simple and batch format json CloudEvent payloads """
    SAMPLE_INPUT = """
        {
            "data": {
              "level": "INFO",
              "message": "Run succeeded - Read 0 messages from source and wrote 0 messages to target",
              "messageType": "CONNECTOR_RUN_COMPLETED"
            },
            "id": "6b9819cf-d004-4dbc-9978-b713e743ad08",
            "oracle": {
              "compartmentid": "comp",
              "ingestedtime": "2024-09-25T20:04:45.926Z",
              "loggroupid": "lgid",
              "logid": "lid",
              "resourceid": "rid",
              "tenantid": "tid"
            },
            "source": "Log_Connector",
            "specversion": "1.0",
            "time": "2024-09-25T20:04:45.130Z",
            "type": "com.oraclecloud.sch.serviceconnector.runlog"
        }
    """

    SAMPLE_OUTPUT = {
        "source": "Log_Connector",
        "time": "2024-09-25T20:04:45.130Z",
        "data":
        {
            "level": "INFO",
            "message": "Run succeeded - Read 0 messages from source and wrote 0 messages to target",
            "messageType": "CONNECTOR_RUN_COMPLETED"
        },
        "ddsource": "oracle_cloud",
        "service": "OCI Logs"
    }


    def setUp(self):
        # Set env variables expected by function
        os.environ['DATADOG_HOST'] = "http://datadog.woof"
        os.environ['DATADOG_TOKEN'] = "VERY-SECRET-TOKEN-2000"
        return super().setUp()

    @mock.patch("requests.post")
    def testSimpleData(self, mock_post, ):
        """ Test single CloudEvent payload """

        payload = TestLogForwarderFunction.SAMPLE_INPUT
        handler(ctx=None, data=to_BytesIO(payload))
        mock_post.assert_called_once()
        self.assertDictEqual(
            TestLogForwarderFunction.SAMPLE_OUTPUT,
            eval(mock_post.mock_calls[0].kwargs['data'])
        )

    @mock.patch("requests.post")
    def testSimpleDataTags(self, mock_post, ):
        """ Test single CloudEvent payload with Tags enabled """

        payload = TestLogForwarderFunction.SAMPLE_INPUT
        os.environ['DATADOG_TAGS'] = "prod:true"
        handler(ctx=None, data=to_BytesIO(payload))
        expected_output = dict(TestLogForwarderFunction.SAMPLE_OUTPUT)
        expected_output['ddtags'] = os.environ['DATADOG_TAGS']
        mock_post.assert_called_once()
        self.assertDictEqual(
            expected_output,
            eval(mock_post.mock_calls[0].kwargs['data'])
        )


    @mock.patch("requests.post")
    def testBatchFormat(self, mock_post):
        """ Test batch format case, where we get an array of 'CloudEvents' """
        batch_count = 10
        payload = f"""
        [
            {",".join([TestLogForwarderFunction.SAMPLE_INPUT] * batch_count)}
        ]
        """
        expected_output = [dict(TestLogForwarderFunction.SAMPLE_OUTPUT)] * batch_count
        handler(ctx=None, data=to_BytesIO(payload))
        self.assertEqual(batch_count, mock_post.call_count, "Data was successfully submitted for the entire batch")
        self.assertEqual(
            expected_output,
            [eval(arg.kwargs['data']) for arg in mock_post.call_args_list]
        )
