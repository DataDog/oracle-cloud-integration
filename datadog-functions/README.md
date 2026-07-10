# Purpose

This folder contains definitions for all of the function images used by the DataDog OCI integration

# Creating docker image

## Local build

- Make sure the current directory is in `datadog-functions`
- For metrics forwarder build, run `docker build -f Dockerfile-metrics --tag <repository-host>/<repository-name>:<tag>  .`
- For log forwarder build, run `docker build -f Dockerfile-logs --tag <repository-host>/<repository-name>:<tag>  .`
- For events forwarder build, run `docker build -f Dockerfile-events --tag <repository-host>/<repository-name>:<tag>  .`
