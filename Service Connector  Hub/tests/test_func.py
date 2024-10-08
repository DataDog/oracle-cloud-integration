import os
import sys
import gzip
from io import BytesIO

# Add the directory containing func.py to the Python path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '../')))

from func import handler, DD_BATCH_SIZE
from unittest import TestCase, mock


def to_bytes_io(inp : str):
    """ Helper function to turn string test data into expected BytesIO asci encoded bytes """
    return BytesIO(bytes(inp, 'ascii'))


def _decompress_string(compressed_string):
    """Decompresses a gzip-compressed string."""
    return gzip.decompress(compressed_string).decode()


def to_decompressed_data(data) -> list[dict] :
    return eval(_decompress_string(data))


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

    SAMPLE_OUTPUT = [
        {
            "source": "Log_Connector",
            "timestamp": "2024-09-25T20:04:45.130Z",
            "data":
            {
                "level": "INFO",
                "message": "Run succeeded - Read 0 messages from source and wrote 0 messages to target",
                "messageType": "CONNECTOR_RUN_COMPLETED"
            },
            "ddsource": "oracle_cloud",
            "service": "OCI Logs"
        }
    ]


    def setUp(self):
        # Set env variables expected by function
        os.environ['DATADOG_HOST'] = "http://datadog.woof"
        os.environ['DATADOG_TOKEN'] = "VERY-SECRET-TOKEN-2000"
        return super().setUp()


    @mock.patch("requests.post")
    def test_simple_data(self, mock_post, ):
        """ Test single CloudEvent payload """

        payload = TestLogForwarderFunction.SAMPLE_INPUT
        mock_post.reset_mock()
        handler(ctx=None, data=to_bytes_io(payload))
        mock_post.assert_called_once()
        self.assertEqual(
            TestLogForwarderFunction.SAMPLE_OUTPUT,
            to_decompressed_data(mock_post.mock_calls[0].kwargs['data'])
        )
        self.assertEqual(
            "gzip",
            mock_post.mock_calls[0].kwargs['headers']['Content-encoding']
        )


    @mock.patch("requests.post")
    def test_simple_data_tags(self, mock_post, ):
        """ Test single CloudEvent payload with Tags enabled """

        payload = TestLogForwarderFunction.SAMPLE_INPUT
        os.environ['DATADOG_TAGS'] = "prod:true"
        handler(ctx=None, data=to_bytes_io(payload))
        expected_output = dict(TestLogForwarderFunction.SAMPLE_OUTPUT[0])
        expected_output['ddtags'] = os.environ['DATADOG_TAGS']
        expected_output = [expected_output]
        mock_post.assert_called_once()
        self.assertEqual(
            expected_output,
            to_decompressed_data(mock_post.mock_calls[0].kwargs['data'])
        )


    @mock.patch("requests.post")
    def test_batch_format(self, mock_post):
        """Test batch format case, where we get an array of 'CloudEvents'."""
        batch_counts = [10, 999, 1000, 1001, 10000]
        for batch_count in batch_counts:
            with self.subTest(msg=f"Batch Count: {batch_count}"):
                mock_post.reset_mock()  # Reset mock_post before each subtest
                payload = f"""
                [
                    {",".join([TestLogForwarderFunction.SAMPLE_INPUT] * batch_count)}
                ]
                """
                total_calls = (batch_count + DD_BATCH_SIZE - 1) // DD_BATCH_SIZE
                handler(ctx=None, data=to_bytes_io(payload))
                self.assertEqual(
                    total_calls, 
                    mock_post.call_count, 
                    "Data was successfully submitted for the entire batch"
                )
                for i in range(total_calls):
                    call_count = DD_BATCH_SIZE if (i < total_calls - 1 or batch_count % DD_BATCH_SIZE == 0) else batch_count % DD_BATCH_SIZE
                    expected_output = [dict(TestLogForwarderFunction.SAMPLE_OUTPUT[0])] * call_count
                    self.assertEqual(
                        expected_output,
                        to_decompressed_data(mock_post.mock_calls[i].kwargs['data'])
                    )
