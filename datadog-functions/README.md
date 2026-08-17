# Purpose

This folder contains definitions for all of the function images used by the DataDog OCI integration

# Creating docker image

## Local build

- Make sure the current directory is in `datadog-functions`
- `--build-arg TAG=<tag>` must match the `--tag` you pass below: it's stamped into the binary at build time so the function can report its own running version back to hubmanager, and Docker does not infer it from `--tag` on its own.
- For metrics forwarder build, run `docker build -f Dockerfile-metrics --build-arg TAG=<tag> --tag <repository-host>/<repository-name>:<tag>  .`
- For log forwarder build, run `docker build -f Dockerfile-logs --build-arg TAG=<tag> --tag <repository-host>/<repository-name>:<tag>  .`
- For events forwarder build, run `docker build -f Dockerfile-events --build-arg TAG=<tag> --tag <repository-host>/<repository-name>:<tag>  .`
