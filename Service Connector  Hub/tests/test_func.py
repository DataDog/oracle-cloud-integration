import os
from io import BytesIO
from func import handler
from unittest import TestCase, mock


def to_BytesIO(str):
    """ Helper function to turn string test data into expected BytesIO asci encoded bytes """
    return BytesIO(bytes(str, 'ascii'))


class TestLogForwarderFunction(TestCase):
    """ Test simple and batch format json CloudEvent payloads """

    def setUp(self):
        # Set env variables expected by function
        os.environ['DATADOG_HOST'] = "http://datadog.woof"
        os.environ['DATADOG_TOKEN'] = "VERY-SECRET-TOKEN-2000"
        return super().setUp()

    @mock.patch("requests.post")
    def testSimpleData(self, mock_post, ):
        """ Test single CloudEvent payload """

        payload = """
        {
            "specversion" : "1.0",
            "type" : "com.example.someevent",
            "source" : "/mycontext",
            "id" : "C234-1234-1234",
            "time" : "2018-04-05T17:31:00Z",
            "comexampleextension1" : "value",
            "comexampleothervalue" : 5,
            "datacontenttype" : "application/json",
            "data" : {
                "appinfoA" : "abc",
                "appinfoB" : 123,
                "appinfoC" : true
            }
        }
        """
        handler(ctx=None, data=to_BytesIO(payload))
        mock_post.assert_called_once()
        self.assertEqual(mock_post.mock_calls[0].kwargs['data'],
                         '{"source": "/mycontext", "time": "2018-04-05T17:31:00Z", "data": '
                         '{"appinfoA": "abc", "appinfoB": 123, "appinfoC": true}, "ddsource": '
                         '"oracle_cloud", "service": "OCI Logs"}'
                         )

    @mock.patch("requests.post")
    def testBatchFormat(self, mock_post):
        """ Test batch format case, where we get an array of 'CloudEvents' """
        batch = """
        [
            {
                "specversion" : "1.0",
                "type" : "com.example.someevent",
                "source" : "/mycontext/4",
                "id" : "B234-1234-1234",
                "time" : "2018-04-05T17:31:00Z",
                "comexampleextension1" : "value",
                "comexampleothervalue" : 5,
                "datacontenttype" : "application/vnd.apache.thrift.binary",
                "data_base64" : "... base64 encoded string ..."
            },
            {
                "specversion" : "1.0",
                "type" : "com.example.someotherevent",
                "source" : "/mycontext/9",
                "id" : "C234-1234-1234",
                "time" : "2018-04-05T17:31:05Z",
                "comexampleextension1" : "value",
                "comexampleothervalue" : 5,
                "datacontenttype" : "application/json",
                "data" : {
                    "appinfoA" : "potatoes",
                    "appinfoB" : 123,
                    "appinfoC" : true
                }
            }
        ]
        """
        handler(ctx=None, data=to_BytesIO(batch))
        self.assertEqual(mock_post.call_count, 2, "Data was not successfully submitted for entire batch")
        self.assertEqual([arg.kwargs['data'] for arg in mock_post.call_args_list],
                         ['{"source": "/mycontext/4", "time": "2018-04-05T17:31:00Z", "data": {}, '
                          '"ddsource": "oracle_cloud", "service": "OCI Logs"}',
                          '{"source": "/mycontext/9", "time": "2018-04-05T17:31:05Z", "data": '
                          '{"appinfoA": "potatoes", "appinfoB": 123, "appinfoC": true}, "ddsource": '
                          '"oracle_cloud", "service": "OCI Logs"}'])
