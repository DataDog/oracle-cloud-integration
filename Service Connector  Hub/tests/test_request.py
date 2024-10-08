import sys
from io import BytesIO
import os
import yaml
import argparse

# Add the directory containing func.py to the Python path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '../')))

from func import handler
import json


def parse_arguments():
    parser = argparse.ArgumentParser(description="Process an optional log event count. If not provided, generate 1 log event.")
    parser.add_argument('--count', type=int, help='Count of log events')
    return parser.parse_args()


def to_bytes_io(inp : str):
    """ Helper function to turn string test data into expected BytesIO asci encoded bytes """
    return BytesIO(bytes(inp, 'ascii'))


def set_environment_variables(config: dict) -> None:
    for key, value in config.items():
        os.environ[key] = str(value)


def read_input_file(file_path: str) -> str:
    with open(file_path) as file:
        return file.read()


def read_config_file(config_path: str) -> dict:
    with open(config_path) as file:
        config = yaml.safe_load(file)['config']
    return config


def main():
    args = parse_arguments()
    count = 1
    if args.count is not None:
        if args.count <= 0:
            print("Error: --count must be greater than 0 if provided.")
            sys.exit(1)
        else:
            count = args.count

    input_file_path = 'tests/input.json'  # Replace with your input file path
    config_file_path = 'func.yaml'  # Replace with your config file path

    input_event = read_input_file(input_file_path)
    config_data = read_config_file(config_file_path)

    #Set Input data
    input_data = input_event
    if count > 1:
        input_events = []
        for i in range(count):
            event = json.loads(input_event)
            event['data']['message'] = f"{i+1}: {event['data']['message']}"
            input_events.append(json.dumps(event))

        input_data = f"""
            [
                {",".join(input_events)}
            ]
            """

    # Set environment variables
    set_environment_variables(config_data)

    # Pass config data to the process function if needed
    handler(ctx=None, data=to_bytes_io(input_data))


if __name__ == "__main__":
    main()
