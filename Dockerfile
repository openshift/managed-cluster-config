FROM openshift/origin-cli:4.12 AS builder

# Multistage with python
FROM ubi8/python-39 AS runner

# Bring oc binary to python image
COPY --from=builder /bin/oc /bin/

# Environment
ARG IN_CONTAINER="true"
ENV REPO_PATH=/managed-cluster-config

# Copy repo into container image:
COPY --chown=default . ${REPO_PATH}
WORKDIR ${REPO_PATH}

# Upgrade pip and install necessasry packages
RUN pip install --disable-pip-version-check oyaml
ADD --chown=default https://github.com/stolostron/policy-generator-plugin/releases/download/v1.9.1/linux-amd64-PolicyGenerator /opt/app-root/bin/PolicyGenerator
RUN chmod +x /opt/app-root/bin/PolicyGenerator

# Make
RUN make

# This image will be replaced by the openshift/release
FROM openshift/origin-cli:4.12

# Ensure make ran as expected
COPY --from=runner /managed-cluster-config/deploy/ deploy
