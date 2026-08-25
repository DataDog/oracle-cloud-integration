from enum import Enum
import json
import subprocess
import argparse
import sys

OK_STATUS = "ok"
ERROR_STATUS = "error"
DEFAULT_DOMAIN_NAME = "Default"
MIN_AVAILABLE_VAULT = 1
DATADOG_VAULT_NAME = "datadog-vault"
DATADOG_COMPARTMENT_NAME = "Datadog"

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
        print("Current user is not in the Default domain: ",domain_name)
    return OK_STATUS

def validate_pre_existing_resources(params, domain_endpoint):
    existing = []
    if _resource_exists(ResourceType.USER, params["user_name"], domain_endpoint=domain_endpoint):
        existing.append(f"User {params['user_name']}")
    if _resource_exists(ResourceType.GROUP, params["user_group_name"], domain_endpoint=domain_endpoint):
        existing.append(f"User Group {params['user_group_name']}")
    if _resource_exists(ResourceType.POLICY, params["user_group_policy_name"], compartment_id=params["tenancy_id"]) \
            and not _policy_owned_by_datadog(params["user_group_policy_name"], params["tenancy_id"]):
        existing.append(f"User Group Policy {params['user_group_policy_name']}")
    if _resource_exists(ResourceType.DYNAMIC_GROUP, params["dg_sch_name"], domain_endpoint=domain_endpoint):
        existing.append(f"Dynamic Group {params['dg_sch_name']}")
    if _resource_exists(ResourceType.DYNAMIC_GROUP, params["dg_fn_name"], domain_endpoint=domain_endpoint):
        existing.append(f"Dynamic Group {params['dg_fn_name']}")
    if _resource_exists(ResourceType.POLICY, params["dg_policy_name"], compartment_id=params["tenancy_id"]) \
            and not _policy_owned_by_datadog(params["dg_policy_name"], params["tenancy_id"]):
        existing.append(f"Dynamic Group Policy {params['dg_policy_name']}")
    if existing:
        return f"{', '.join(existing)} already exists."
    return OK_STATUS

def _vault_exists(tenancy_ocid, home_region, compartment_id):
    """Return True if the datadog-vault already exists, so re-apply does not trip the quota check."""
    if not compartment_id:
        # Look up the auto-created Datadog compartment under the tenancy.
        try:
            cmd = [
                "oci", "iam", "compartment", "list",
                "--compartment-id", tenancy_ocid,
                "--name", DATADOG_COMPARTMENT_NAME,
                "--query", "data[?\"lifecycle-state\"=='ACTIVE'].id | [0]",
                "--raw-output",
            ]
            compartment_id = subprocess.check_output(cmd).decode().strip()
        except Exception:
            return False
    if not compartment_id or compartment_id == "null":
        return False
    try:
        cmd = [
            "oci", "kms", "management", "vault", "list",
            "--compartment-id", compartment_id,
            "--region", home_region,
            "--query", f"data[?\"display-name\"=='{DATADOG_VAULT_NAME}' && \"lifecycle-state\"=='ACTIVE'] | [0]",
            "--raw-output",
        ]
        result = subprocess.check_output(cmd).decode().strip()
        return bool(result and result != "null")
    except Exception:
        return False

def _policy_owned_by_datadog(name, compartment_id):
    """Return True if the named IAM policy exists and carries the ownedby=datadog tag."""
    cmd = [
        "oci", "iam", "policy", "list",
        "--compartment-id", compartment_id,
        "--all",
        "--query", f"data[?name=='{name}'] | [0]",
        "--raw-output",
    ]
    try:
        result = subprocess.check_output(cmd).decode().strip()
        if not result or result == "null":
            return False
        policy = json.loads(result)
        return policy.get("freeform-tags", {}).get("ownedby") == "datadog"
    except Exception:
        return False

def validate_vault_quota(tenancy_ocid, home_region, compartment_id):
    if _vault_exists(tenancy_ocid, home_region, compartment_id):
        return OK_STATUS
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

def validate_existing_vault(existing_home_region_vault_id, home_region, compartment_id):
    """When existing_home_region_vault_id is set, confirm the vault, its
    datadog-key, and its DatadogAPIKey secret are all usable (vault ACTIVE, key
    ENABLED, secret ACTIVE). Fails at precheck time (rather than later at apply)
    on a typo, a non-existent OCID, or any of the three still being in a
    pending-deletion state. The secret is reused as-is, so it must be ACTIVE —
    its stored content is the API key the forwarder reads.
    """
    # 1. Vault must exist, be ACTIVE, and be named datadog-vault.
    vault_cmd = [
        "oci", "kms", "management", "vault", "get",
        "--vault-id", existing_home_region_vault_id,
        "--region", home_region,
        "--query", "data",
        "--raw-output",
    ]
    try:
        result = subprocess.check_output(vault_cmd).decode().strip()
    except subprocess.CalledProcessError:
        return f"existing_home_region_vault_id '{existing_home_region_vault_id}' could not be read (not found or no permission)."
    except Exception as e:
        return f"Failed to validate existing_home_region_vault_id '{existing_home_region_vault_id}': {str(e)}"
    if not result or result == "null":
        return f"existing_home_region_vault_id '{existing_home_region_vault_id}' does not resolve to a vault."
    vault = json.loads(result)
    if vault.get("lifecycle-state") != "ACTIVE":
        return (f"existing_home_region_vault_id '{existing_home_region_vault_id}' is in state '{vault.get('lifecycle-state')}', not ACTIVE. "
                f"Cancel the deletion of the existing datadog-vault to restore it to ACTIVE.")
    if vault.get("display-name") != DATADOG_VAULT_NAME:
        return (f"existing_home_region_vault_id '{existing_home_region_vault_id}' is named '{vault.get('display-name')}', not '{DATADOG_VAULT_NAME}'. "
                f"It must point at a vault created by a previous Datadog install.")
    management_endpoint = vault.get("management-endpoint")
    # The vault's own compartment-id is the authoritative compartment for its
    # key/secret. The caller may pass an empty compartment_id (the stack
    # auto-creates the Datadog compartment after the precheck, so its OCID is
    # not known at precheck time), so prefer the vault's compartment-id.
    vault_compartment_id = vault.get("compartment-id") or compartment_id
    if not vault_compartment_id:
        return "Cannot validate the existing vault's key/secret: could not resolve the vault's compartment."

    # 2. The vault must contain an ENABLED datadog-key.
    key_cmd = [
        "oci", "kms", "management", "key", "list",
        "--endpoint", management_endpoint,
        "--compartment-id", vault_compartment_id,
        "--region", home_region,
        "--all",
        "--query", f"data[?\"display-name\"=='datadog-key' && \"lifecycle-state\"=='ENABLED'] | [0]",
        "--raw-output",
    ]
    try:
        key_result = subprocess.check_output(key_cmd).decode().strip()
    except Exception as e:
        return f"Failed to list keys in existing_home_region_vault_id '{existing_home_region_vault_id}': {str(e)}"
    if not key_result or key_result == "null":
        return (f"existing_home_region_vault_id '{existing_home_region_vault_id}' has no ENABLED key named 'datadog-key'. "
                f"Cancel the deletion of the existing datadog-key to restore it to ENABLED.")

    # 3. The vault must contain an ACTIVE DatadogAPIKey secret (reused as-is).
    secret_cmd = [
        "oci", "vault", "secret", "list",
        "--compartment-id", vault_compartment_id,
        "--vault-id", existing_home_region_vault_id,
        "--region", home_region,
        "--all",
        "--query", f"data[?\"secret-name\"=='DatadogAPIKey' && \"lifecycle-state\"=='ACTIVE'] | [0]",
        "--raw-output",
    ]
    try:
        secret_result = subprocess.check_output(secret_cmd).decode().strip()
    except Exception as e:
        return f"Failed to list secrets in existing_home_region_vault_id '{existing_home_region_vault_id}': {str(e)}"
    if not secret_result or secret_result == "null":
        return (f"existing_home_region_vault_id '{existing_home_region_vault_id}' has no ACTIVE secret named 'DatadogAPIKey'. "
                f"Cancel the deletion of the existing DatadogAPIKey secret to restore it to ACTIVE — "
                f"it is reused as-is (its stored content is the API key the forwarder reads).")
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
    parser.add_argument("--compartment-id", required=False, default="")
    parser.add_argument("--existing-home-region-vault-id", required=False, default="")
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
        "compartment_id": args.compartment_id,
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

    # Validation 5: Vault quota check (skipped when vault already exists — idempotent re-apply —
    # or when the customer is reusing an existing home-region vault via
    # existing_home_region_vault_id, in which case no vault is created and quota is irrelevant).
    # When reusing, validate the OCID resolves to an ACTIVE datadog-vault so a typo or
    # pending-deletion vault fails here, not later at apply.
    if args.existing_home_region_vault_id:
        result = validate_existing_vault(args.existing_home_region_vault_id, params["home_region"], params["compartment_id"])
        if result != OK_STATUS:
            errors.append(result)
    else:
        result = validate_vault_quota(params["tenancy_id"], params["home_region"], params["compartment_id"])
        if result != OK_STATUS:
            errors.append(result)

    if errors:
        print(json.dumps({"error": "; ".join(errors), "status": ERROR_STATUS}))
        sys.exit(1)
    else:
        print(json.dumps({"status": OK_STATUS}))


if __name__ == "__main__":
    main()
