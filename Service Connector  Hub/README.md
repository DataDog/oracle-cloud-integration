# Service Connector Hub function
OCI function used for log forwarding. See [DataDog documentation for more info](https://docs.datadoghq.com/integrations/oracle_cloud_infrastructure/?tab=serviceconnectorhub#oci-function).

## Send Test Log Events to Datadog
This guide will help you test sending log events to Datadog. Follow the steps below to install dependencies, configure your API key, and send test log events.

### Step 1: Install Dependencies
First, install the required dependencies listed in the `requirements.txt` file. You can do this using `pip`:

```sh
pip install -r requirements.txt
```

### Step 2: Configure API Key
Before sending log events, you need to add your Datadog API key to the `func.yaml` file. Open `func.yaml` and set the DATADOG_TOKEN variable to your API key:

```
DATADOG_TOKEN: your_datadog_api_key_here
```
You can optionally add tags as well by updating `DATADOG_TAGS` field.

### Step 3: Prepare Input Data
Ensure that the `input.json` file contains the message you want to send. The message should include a `time` field. You will need to update this field to be within 18 hours of the current time.

### Step 4: Send Test Log Events
You can now send test log events using the `make_test_request.py` script. You can pass an optional parameter `--count` to indicate the number of messages to be produced. The message will be published the specified number of times. `cd` into the current directory.

```commandline
python tests/make_test_request.py --count=<count>
```
**Notes**
- Ensure that the `time` field in the message in `input.json` is updated to be within 18 hours of the current time before running the script. 
- The script will validate that the `--count` parameter is greater than 0 if provided.

By following these steps, you can test sending log events to Datadog.

## Tests

To run tests, cd into the current directory and run:

`python3 -m unittest`
