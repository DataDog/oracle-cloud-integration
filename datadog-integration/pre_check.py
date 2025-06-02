from enum import Enum
import json
import subprocess
import argparse
import sys

OK_STATUS = "ok"
ERROR_STATUS = "error"
DEFAULT_DOMAIN_NAME = "Default"
MIN_AVAILABLE_VAULT = 1
MIN_AVAILABLE_CONNECTOR_HUB = 1

class ResourceType(Enum):
    USER = "user"
    GROUP = "group"
    POLICY = "policy"
    DYNAMIC_GROUP = "dynamic_group"

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
    return OK_STATUS

def validate_home_region_support(home_region, supported_regions):
    if home_region not in supported_regions:
        return f"Home region {home_region} is not supported by Datadog."
    return OK_STATUS

def validate_default_domain(domain_name):
    if domain_name != DEFAULT_DOMAIN_NAME:
        return "Current user is not in the default domain."
    return OK_STATUS

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
    return OK_STATUS

def validate_vault_quota(tenancy_ocid, home_region):
    cmd = [
        "oci", "limits", "resource-availability", "get",
        "--service-name", "kms",
        "--limit-name", "virtual-vault-count",
        "--compartment-id", tenancy_ocid,
        "--region", home_region
    ]
    try:
        result = subprocess.check_output(cmd).decode()
        data = json.loads(result)
        available = data["data"].get("available", 0)
        if available < MIN_AVAILABLE_VAULT:
            return "No vaults can be created: vault quota exhausted."
        return OK_STATUS
    except Exception as e:
        return f"Failed to check vault quota: {str(e)}"

def validate_connector_hub_quota(tenancy_ocid, home_region):
    cmd = [
        "oci", "limits", "resource-availability", "get",
        "--service-name", "service-connector-hub",
        "--limit-name", "service-connector-count",
        "--compartment-id", tenancy_ocid,
        "--region", home_region
    ]
    try:
        result = subprocess.check_output(cmd).decode()
        data = json.loads(result)
        available = data["data"].get("available", 0)
        if available < MIN_AVAILABLE_CONNECTOR_HUB:
            return f"Insufficient connector hub quota in region {home_region}: {available} available, {MIN_AVAILABLE_CONNECTOR_HUB} required."
    except Exception as e:
        return f"Failed to check connector hub quota in region {home_region}: {str(e)}"
    return OK_STATUS

def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tenancy-id", required=True)
    parser.add_argument("--is-home-region", required=True)
    parser.add_argument("--home-region", required=True)
    parser.add_argument("--supported-regions", required=True)
    parser.add_argument("--user-id", required=True)
    parser.add_argument("--user-name", required=True)
    parser.add_argument("--user-group-name", required=True)
    parser.add_argument("--user-group-policy-name", required=True)
    parser.add_argument("--dg-sch-name", required=True)
    parser.add_argument("--dg-fn-name", required=True)
    parser.add_argument("--dg-policy-name", required=True)
    parser.add_argument("--domain-display-name", required=True)
    parser.add_argument("--idcs-endpoint", required=True)
    return parser.parse_args()

def main():
    args = parse_args()
    params = {
        "user_id": args.user_id,
        "tenancy_id": args.tenancy_id,
        "home_region": args.home_region,
        "is_home_region": str(args.is_home_region).lower() == "true",
        "supported_regions": json.loads(args.supported_regions),
        "user_name": args.user_name,
        "user_group_name": args.user_group_name,
        "user_group_policy_name": args.user_group_policy_name,
        "dg_sch_name": args.dg_sch_name,
        "dg_fn_name": args.dg_fn_name,
        "dg_policy_name": args.dg_policy_name,
        "domain_display_name": args.domain_display_name,
        "idcs_endpoint": args.idcs_endpoint,
    }

    errors = []

    # Validation 1: Home region check
    result = validate_home_region(params["is_home_region"])
    if result != OK_STATUS:
        errors.append(result)

    # Validation 2: Home region support check
    result = validate_home_region_support(params["home_region"], params["supported_regions"])
    if result != OK_STATUS:
        errors.append(result)
    
    # Find domain name and domain endpoint for further checks
    if params["domain_display_name"] is not None and params["idcs_endpoint"] is not None:
        # Validation 3: Default domain check
        result = validate_default_domain(params["domain_display_name"])
        if result != OK_STATUS:
            errors.append(result)
        
        # Validation 4: Pre-existing resources check
        result = validate_pre_existing_resources(params, params["idcs_endpoint"])
        if result != OK_STATUS:
            errors.append(result)
    else:
        errors.append("User not found in any domain")

    # Validation 5: Vault quota check
    result = validate_vault_quota(params["tenancy_id"], params["home_region"])
    if result != OK_STATUS:
        errors.append(result)

    # Validation 6: Connector hub quota check
    result = validate_connector_hub_quota(params["tenancy_id"], params["home_region"])
    if result != OK_STATUS:
        errors.append(result)

    if errors:
        print(json.dumps({"error": "; ".join(errors), "status": ERROR_STATUS}))
        sys.exit(1)
    else:
        print(json.dumps({"status": OK_STATUS}))


if __name__ == "__main__":
    main()
