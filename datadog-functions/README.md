# Creating docker image


## Local build
- Make sure the current directory is in `datadog-functions`
- For metrics forwarder build, run `docker build -f Dockerfile-metrics --tag <repository-host>/<repository-name>:<tag>  .`
- For log forwarder build, run `docker build -f Dockerfile-logs --tag <repository-host>/<repository-name>:<tag>  .`