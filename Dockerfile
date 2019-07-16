FROM openshift/origin-cli:v3.11 AS builder

RUN cp /bin/oc /

# Multistage with python
FROM python:2.7.15 AS runner

# Bring oc binary to python image
COPY --from=builder /oc /bin/

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

# This image will be replaced by the openshift/release
FROM openshift/origin-cli

# Ensure make ran as expected
COPY --from=runner /managed-cluster-config/deploy/ deploy
