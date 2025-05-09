#!/usr/bin/env python3
import os
import subprocess
import json
import sys

def get_stack_id(job_id):
    if not job_id:
        return {"stack_id": ""}
    try:
        cmd = [
            "oci", "resource-manager", "job", "get",
            "--job-id", job_id,
            "--query", 'data."stack-id"',
            "--raw-output"
        ]
        stack_id = subprocess.check_output(cmd, universal_newlines=True).strip()
        return {"stack_id": stack_id}
    except subprocess.CalledProcessError as e:
        return {"error": f"OCI CLI call failed: {str(e)}"}
    except Exception as e:
        return {"error": f"Unexpected error: {str(e)}"}

if __name__ == "__main__":
    try:
        # Read dummy stdin input for Terraform external provider (required)
        _ = json.load(sys.stdin)
        job_id = os.getenv("JOB_ID")
        result = get_stack_id(job_id)
        print(json.dumps(result))
        sys.exit(0)
    except Exception as e:
        print(json.dumps({"error": f"Script failure: {str(e)}"}))
        sys.exit(1)