resource "null_resource" "Login2OCIR" {
    provisioner "local-exec" {
        command = <<EOT
            #!/bin/bash
            set -e

            for i in {1..5}; do
                echo "$auth_token" | docker login ${local.registry_domain} --username ${local.tenancy_namespace}/${var.username} --password-stdin && break
                echo "Retrying Docker login... attempt $i"
                sleep 10
            done

            # Check if login was successful
            if [ $i -eq 5 ]; then
                echo "Error: Docker login failed after 5 attempts. Trying to login through Oracle Identity Cloud Service"
                for j in {1..5}; do
                    echo "$auth_token" | docker login ${local.registry_domain} --username ${local.tenancy_namespace}/oracleidentitycloudservice/${var.username} --password-stdin && break
                    echo "Retrying Docker login through Identity service... attempt $j"
                    sleep 5
                done
                if [ $j -eq 5 ]; then
                    echo "Error: Docker login failed after 5 attempts."
                    exit 1
                fi
            fi
        EOT
    }
    triggers = {
        always_run = "${timestamp()}"
    }
}
