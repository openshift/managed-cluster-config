FROM openshift/origin-cli:v3.11

# Multistage with python
FROM python:2.7

# Bring oc binary to python image
COPY --from=0 /bin/oc /bin/

# Environment
ARG IN_DOCKER_CONTAINER="true"
ENV REPO_PATH=/managed-cluster-config

# Copy repo into docker image:
COPY . ${REPO_PATH}
WORKDIR ${REPO_PATH}

# Upgrade pip and install necessasry packages
RUN pip install pyyaml

# Make
RUN make 