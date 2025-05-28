#!/usr/bin/env python3

# NOTE: If you update this script, run `./generate_configmap.sh`

import sys

# should_patch.py takes two arguments: version and compare_version.
# It will then compare the Z stream of version to see if it's >= compare_version,
# exiting non-zero if it's not. Exiting non-zero means we need to patch.
#
# Example:
#   # This exits non-zero as the Z stream (10) is not >= 11
#   python should_patch.py 4.17.10 11
#
#   # This exits zero as the Z stream (10) is >= 9
#   python should_patch.py 4.17.10 9

usage = """usage: python should_patch.py $version $compare_version
example: python should_patch.py 4.17.15 14 # exits 0 
"""

def should_patch(version, compare_version):
    try:
        x, y, z = version.split('.')
        if int(z) >= int(compare_version):
            print(f"don't patch: version {version} is >= x.y.{compare_version}")
            return False
        else:
            print(f"should patch: version {version} is not >= x.y.{compare_version}")
            return True
    except ValueError:
        print(f"could not compare version {version} to {compare_version}, defaulting to should patch")
        return True

def main():
    if len(sys.argv) != 3:
        print(usage)
        sys.exit(1)

    version = sys.argv[1].rstrip()
    compare_version = sys.argv[2].rstrip()

    if should_patch(version, compare_version):
        sys.exit(1)

if __name__=="__main__":
    main()
