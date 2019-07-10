FROM openshift/origin-cli:v3.11

# Environment
ARG IN_DOCKER_CONTAINER="true"
ENV VENV=/venv
ENV REPO_PATH=/managed-cluster-config

# Copy repo into docker image:
COPY . ${REPO_PATH}
WORKDIR ${REPO_PATH}

# Docker dependencies:
RUN yum update -y && yum install -y \
    git \
    make \
    epel-release
RUN yum -y install python-pip && yum clean all

# Upgrade pip and install necessasry packages
RUN pip install \
    --upgrade pip \
    virtualenv \
    pyyaml

# Set up venv
RUN virtualenv -p /usr/bin/python2.7 ${VENV} && \
    . ${VENV}/bin/activate

# Make
RUN make 