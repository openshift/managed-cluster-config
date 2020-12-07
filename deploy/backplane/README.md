# Backplane RBAC
This directory is focused around managing roles for backplane users based on their team. The goal is to maintain least access privileges.

| Directory  | Description   |
|---|---|
| cee  | RBAC for users from CEE  |
| srep  | RABC for SRE Platform team  |
|  elevated-sre | RBAC for cluster admin. Used as an elevation strategy for break-glass   |
| layered-sre  | RBAC for SRE managing layered products or add-ons in OSD clusters. This has subdirectories for each available add-on |