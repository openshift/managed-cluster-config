FROM registry.svc.ci.openshift.org/openshift/release:golang-1.12 AS builder
WORKDIR /go/src/github.com/openshift/managed-cluster-config
COPY . .
RUN NO_DOCKER=1 make build

FROM registry.svc.ci.openshift.org/openshift/origin-v4.0:base
