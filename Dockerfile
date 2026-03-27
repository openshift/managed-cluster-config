FROM registry.redhat.io/openshift4/ose-cli:v4.15 AS builder

# Bring promtool from prometheus image
FROM quay.io/prometheus/prometheus AS promtool

# Multistage with python
FROM registry.redhat.io/ubi9/python-312:9.7 AS runner

# Bring oc binary to python image
COPY --from=builder /bin/oc /bin/

# Bring promtool binary from prometheus image
COPY --from=promtool /bin/promtool /bin/

# Install dependencies for PR checks and build
USER root
RUN dnf install -y jq git diffutils && dnf clean all
USER default

# Environment
ARG IN_CONTAINER="true"
ENV REPO_PATH=/managed-cluster-config

# Copy repo into container image:
COPY --chown=default . ${REPO_PATH}
WORKDIR ${REPO_PATH}

# Upgrade pip and install necessasry packages
RUN pip install --disable-pip-version-check oyaml
ADD --chown=default https://github.com/open-cluster-management-io/policy-generator-plugin/releases/download/v1.9.1/linux-amd64-PolicyGenerator /opt/app-root/bin/PolicyGenerator
RUN chmod +x /opt/app-root/bin/PolicyGenerator
