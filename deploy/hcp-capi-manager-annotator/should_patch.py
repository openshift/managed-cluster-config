#!/usr/bin/env python3

# NOTE: If you update this script, run `./generate_configmap.sh`

# should_patch.py decides what to do with the
# hypershift.openshift.io/capi-manager-image annotation on a HostedCluster,
# based on the cluster's OpenShift version.
#
# HyperShift pins the core CAPI manager (cluster-capi-controllers) itself for
# payloads below 4.21 only on the 5.0 codebase. On the 4.21/4.22 HyperShift
# branches a 4.19 or 4.20 hosted cluster gets no pin, so it runs a CAPI
# controller that writes status through v1beta1. With CAPI v1beta2 in play that
# drops status.phase and congests the API server with conversion traffic.
#
# Exit codes:
#   0  remove the annotation (4.21 and later: payload or HyperShift decide)
#   1  pin the annotation (4.19 and 4.20)
#   2  skip the cluster (version could not be parsed)

import sys

# 4.20 was the last version shipping a CAPI controller that writes v1beta1.
MIN_PINNED_MINOR = 21


def parse_version(version):
    parts = version.strip().split(".")
    if len(parts) < 2:
        raise ValueError(f"could not parse version {version!r}")
    return int(parts[0]), int(parts[1])


def action(version):
    try:
        major, minor = parse_version(version)
    except ValueError as err:
        print(err)
        return "skip"
    if major == 4 and minor < MIN_PINNED_MINOR:
        return "pin"
    return "remove"


def needs_pin(version):
    return action(version) == "pin"


def main():
    if len(sys.argv) != 2:
        print("usage: python should_patch.py $version")
        sys.exit(2)

    result = action(sys.argv[1])
    print(f"version {sys.argv[1]}: {result}")
    sys.exit({"pin": 1, "remove": 0, "skip": 2}[result])


if __name__ == "__main__":
    main()
