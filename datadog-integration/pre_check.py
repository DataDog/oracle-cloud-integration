from enum import Enum
import sys
import json
import subprocess
import os

DEFAULT_DOMAIN_NAME = "Default"
MIN_VAULT_QUOTA = 1
MIN_CONNECTOR_HUB_QUOTA_PER_REGION = 1
MARKER_DIR = os.path.join(os.getcwd(), ".terraform")
MARKER_FILE = os.path.join(MARKER_DIR, "dd_prechecks_done")

class ResourceType(Enum):
    USER = "user"
    GROUP = "group"
    POLICY = "policy"
    DYNAMIC_GROUP = "dynamic_group"

def find_user_domain(user_ocid, tenancy_ocid):
    """
    Returns (domain_display_name, domain_endpoint) for the user if found, else (None, None)
    """
    domains = _list_domains(tenancy_ocid)
    for domain in domains:
        endpoint = domain["url"]
        cmd = [
            "oci", "identity-domains", "users", "list",
            "--endpoint", endpoint,
            "--query", f"data.resources[?ocid=='{user_ocid}'] | [0]",
            "--raw-output"
        ]
        try:
            result = subprocess.check_output(cmd).decode().strip()
            if result and result != 'null':
                return domain["display_name"], endpoint
        except Exception:
            pass
    return None, None

def _list_domains(tenancy_ocid):
    cmd = [
        "oci", "iam", "domain", "list",
        "--all",
        "--compartment-id", tenancy_ocid,
        "--query", "data[].{id:id, url:url, display_name:\"display-name\"}",
        "--raw-output"
    ]
    result = subprocess.check_output(cmd).decode()
    try:
        domains = json.loads(result)
    except Exception:
        # Fallback for raw-output as lines
        domains = [json.loads(line) for line in result.strip().split('\n') if line.strip()]
    return domains

def _resource_exists(resource_type: ResourceType, name, domain_endpoint=None, compartment_id=None):
    if resource_type == ResourceType.USER:
        cmd = [
            "oci", "identity-domains", "users", "list",
            "--endpoint", domain_endpoint,
            "--query", f"data.resources[?\"display-name\"=='{name}'] | [0]",
            "--raw-output"
        ]
    elif resource_type == ResourceType.GROUP:
        cmd = [
            "oci", "identity-domains", "groups", "list",
            "--endpoint", domain_endpoint,
            "--query", f"data.resources[?\"display-name\"=='{name}'] | [0]",
            "--raw-output"
        ]
    elif resource_type == ResourceType.POLICY:
        cmd = [
            "oci", "iam", "policy", "list",
            "--compartment-id", compartment_id,
            "--query", f"data[?name=='{name}'] | [0]",
            "--raw-output"
        ]
    elif resource_type == ResourceType.DYNAMIC_GROUP:
        cmd = [
            "oci", "identity-domains", "dynamic-resource-groups", "list",
            "--endpoint", domain_endpoint,
            "--query", f"data.resources[?\"display-name\"=='{name}'] | [0]",
            "--raw-output"
        ]
    else:
        return False
    result = subprocess.check_output(cmd).decode().strip()
    return bool(result and result != 'null')

def validate_home_region(is_home_region):
    if not is_home_region:
        return "Current user is not in the home region."
    return "ok"

def validate_default_domain(domain_name):
    if domain_name != DEFAULT_DOMAIN_NAME:
        return "Current user is not in the default domain."
    return "ok"

def validate_pre_existing_resources(params, domain_endpoint):
    existing = []
    if _resource_exists(ResourceType.USER, params["user_name"], domain_endpoint=domain_endpoint):
        existing.append(f"User {params['user_name']}")
    if _resource_exists(ResourceType.GROUP, params["user_group_name"], domain_endpoint=domain_endpoint):
        existing.append(f"User Group {params['user_group_name']}")
    if _resource_exists(ResourceType.POLICY, params["user_group_policy_name"], compartment_id=params["tenancy_id"]):
        existing.append(f"User Group Policy {params['user_group_policy_name']}")
    if _resource_exists(ResourceType.DYNAMIC_GROUP, params["dg_sch_name"], domain_endpoint=domain_endpoint):
        existing.append(f"Dynamic Group {params['dg_sch_name']}")
    if _resource_exists(ResourceType.DYNAMIC_GROUP, params["dg_fn_name"], domain_endpoint=domain_endpoint):
        existing.append(f"Dynamic Group {params['dg_fn_name']}")
    if _resource_exists(ResourceType.POLICY, params["dg_policy_name"], compartment_id=params["tenancy_id"]):
        existing.append(f"Dynamic Group Policy {params['dg_policy_name']}")
    if existing:
        return f"{', '.join(existing)} already exists."
    return "ok"

def validate_vault_quota(tenancy_ocid):
    cmd = [
        "oci", "limits", "resource-availability", "get",
        "--service-name", "kms",
        "--limit-name", "virtual-vault-count",
        "--compartment-id", tenancy_ocid
    ]
    try:
        result = subprocess.check_output(cmd).decode()
        data = json.loads(result)
        available = data["data"].get("available", 0)
        if available < MIN_VAULT_QUOTA:
            return "No vaults can be created: vault quota exhausted."
        else:
            return "ok"
    except Exception as e:
        return f"Failed to check vault quota: {str(e)}"

def validate_connector_hub_quota(tenancy_ocid, supported_regions):
    insufficient = []
    for region in supported_regions:
        cmd = [
            "oci", "limits", "resource-availability", "get",
            "--service-name", "service-connector-hub",
            "--limit-name", "service-connector-count",
            "--compartment-id", tenancy_ocid,
            "--region", region
        ]
        try:
            result = subprocess.check_output(cmd).decode()
            data = json.loads(result)
            available = data["data"].get("available", 0)
            if available < MIN_CONNECTOR_HUB_QUOTA_PER_REGION:
                insufficient.append(region)
        except Exception as e:
            print(f"Failed to check connector hub quota in region {region}: {str(e)}")
    if insufficient:
        return f"Insufficient connector hub quota in regions: {', '.join(insufficient)}"
    return "ok"

def main():
    # If marker file exists, always return success
    if not os.path.exists(MARKER_DIR):
        os.makedirs(MARKER_DIR)
        
    if os.path.exists(MARKER_FILE):
        print(json.dumps({"status": "ok"}))
        return

    params = json.load(sys.stdin)
    user_id = params["user_id"]
    tenancy_ocid = params.get("tenancy_id")
    # supported_regions is passed as a JSON string from Terraform external data source
    supported_regions = json.loads(params.get("supported_regions", "[]"))

    errors = []
    # Find domain name and domain endpoint for further checks
    domain_name, domain_endpoint = find_user_domain(user_id, tenancy_ocid)

    # Validation 1: Home region check
    is_home_region = params.get("is_home_region", "false").lower() == "true"
    result = validate_home_region(is_home_region)
    if result != "ok":
        errors.append(result)
    
    # Validation 2: Default domain check
    result = validate_default_domain(domain_name)
    if result != "ok":
        errors.append(result)
    
    # Validation 3: Pre-existing resources check
    result = validate_pre_existing_resources(params, domain_endpoint)
    if result != "ok":
        errors.append(result)

    # Validation 4: Vault quota check
    result = validate_vault_quota(tenancy_ocid)
    if result != "ok":
        errors.append(result)

    # Validation 5: Connector hub quota check
    result = validate_connector_hub_quota(tenancy_ocid, supported_regions)
    if result != "ok":
        errors.append(result)

    if errors:
        print(json.dumps({"error": "; ".join(errors), "status": "error"}))
    else:
        # On first success, create marker file
        with open(MARKER_FILE, "w") as f:
            f.write("OCI Datadog pre-checks passed. DO NOT DELETE this file unless you want pre-checks to run again.\n")
        print(json.dumps({"status": "ok"}))


if __name__ == "__main__":
    main()
