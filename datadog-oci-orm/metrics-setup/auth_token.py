import json
import sys
import subprocess
import traceback


def _remove_existing_tokens(token_ids: list, user_ocid: str, region: str) -> None:
  """
  Removes existing token if any for a user based on token id list, user_ocid and region
  """
  try:
    for token in token_ids:
      cmd = ["oci", "iam", "auth-token", "delete", "--auth-token-id", token.strip(), "--user-id", user_ocid, "--region", region, "--force"]
      subprocess.check_output(cmd, text=True)
  except subprocess.CalledProcessError as e:
      raise ChildProcessError(f"Error in removing tokens for user: {user_ocid} {e.output}") from e


def _regenerate_token(json_string:str) -> None:
  """
  Remove existing tokens and create a new API token. The json string is in the following format.
  {"user_ocid: "id", "region": "oci_home_region", "token_ids":"t1,t2"}. Token ids are comma separated values.
  """
  input_json = json.loads(json_string)
  user_ocid, region, token_ids = input_json["user_ocid"], input_json["region"], input_json["token_ids"].strip()
  if token_ids:
    token_ids = token_ids.split(",")
    _remove_existing_tokens(token_ids, user_ocid, region)
  try:
    cmd = ["oci", "iam", "auth-token", "create", "--user-id", user_ocid, "--description", "autogen token", "--region", region]
    output = subprocess.check_output(cmd, text=True)
    result = json.loads(output)["data"]
    output_data = {"token_id" : result["id"], "token" : result["token"]}
    json_value = {"output" : json.dumps(output_data)}
    print(json.dumps(json_value))
  except subprocess.CalledProcessError as e:
    raise ChildProcessError(f"Error in creating token for user: {user_ocid} {e.output}") from e


if __name__ == "__main__":
    input_json = sys.stdin.read()
    if not input_json:
      print("No Json provided", file=sys.stderr)
      sys.exit(1)
    err, trace = None, None
    try:
      _regenerate_token(input_json)
      sys.exit(0)
    except Exception as e:
      trace = traceback.format_exc()
      err = e
    if trace:
      print("Error:", err, trace, file=sys.stderr)
      sys.exit(1)
