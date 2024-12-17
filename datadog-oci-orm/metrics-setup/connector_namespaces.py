import json
import sys

MAX_NAMESPACES_PER_BATCH = 50
MAX_COMPARTMENTS_PER_BATCH = 5
NAMESPACES_CONST = "namespaces"


def balance_connector_hub_batches(json_string) -> None:
  """
  Takes an input json string which is a list of dictionary. Each dicionary having compartment id and namespace list as fields
  and prints out json string containing batches of compartments and namespaces.
  Example input: 
  [
    {"compartment": "c1": "namespaces":["n1, "n2"]}, 
    {"compartment": "c2": "namespaces":["n1, "n2"]}, 
    {"compartment": "c3": "namespaces":["n1, "n2"]}
  ]
  Prints out a json with list of batches of compartments and namespace. The maximum size based on either maximum allowed compartments in a connector hub or 
  maximum namespaces allowed in a connector hub.

  Example output: ->
  [
    [
      {"compartment": "c1": "namespaces":["n1, "n2"]}, 
      {"compartment": "c2": "namespaces":["n1, "n2"]}, 
    ],
    [
      {"compartment": "c3": "namespaces":["n1, "n2"]}
    ]
  ]
  """  
  json_string = json_string.replace("\\", "")
  compartment_namespace_list = json.loads(json_string)
  batches, current_batch = [], []
  batch_namespace_count = 0
  for comp in compartment_namespace_list:
    namespaces = comp[NAMESPACES_CONST]
    if (len(namespaces) + batch_namespace_count) > MAX_NAMESPACES_PER_BATCH or len(current_batch) == MAX_COMPARTMENTS_PER_BATCH:
      batches.append(current_batch)
      batch_namespace_count = 0
      current_batch = []
    current_batch.append(comp)
    batch_namespace_count += len(namespaces)
  if current_batch:
    batches.append(current_batch)
  json_value = {"output" : json.dumps(batches)}
  print(json.dumps(json_value))

if __name__ == "__main__":
    if len(sys.argv) <= 1:
      print("No Json provided", file=sys.stderr)
      sys.exit(1)
    try:
      input_json = sys.argv[1]
      balance_connector_hub_batches(input_json)
      sys.exit(0)
    except ValueError as e:
      print("Error decoding Json: ", input_json, e, file=sys.stderr)
    except Exception as e:
      print("Error processing namespaces", e, file=sys.stderr)
    sys.exit(1)