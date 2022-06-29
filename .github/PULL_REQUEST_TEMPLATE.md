### What type of PR is this?
_(bug/feature/cleanup/documentation)_

### What this PR does / why we need it?

### Which Jira/Github issue(s) this PR fixes?

_Fixes #_

### Special notes for your reviewer:

### Pre-checks (if applicable):
- [ ] Tested latest changes against a cluster
- [ ] Included documentation changes with PR
- [ ] If this is a new object that is not intended for the FedRAMP environment (if unsure, please reach out to team FedRAMP), please exclude it with:

    ```yaml
    matchExpressions:
    - key: api.openshift.com/fedramp
      operator: NotIn
      values: ["true"]
    ```
