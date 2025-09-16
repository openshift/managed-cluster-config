# Validating Admission Policy to prevent HCP node image-type modification

Reference card: SREP-1090

## Test cases
We can use [CEL playground](https://playcel.undistro.io/) to experiment the CEL in the `ValidatingAdmissionPolicy`.

### Case 1 - Users should not be allowed to remove the label `api.openshift.com/image-type`.
Input:
```
object:
  metadata:
    labels: {}
oldObject:
  metadata:
    labels:
      api.openshift.com/image-type: windows
```

Expected Output:
```
false  (deny)
```

### Case 2 - Users should not be allowed to add the label `api.openshift.com/image-type`.
Input:
```
object:
  metadata:
    labels:
      api.openshift.com/image-type: windows
oldObject:
  metadata:
    labels: {}
```

Expected Output:
```
false  (deny)
```

### Case 3 - Users should not be allowed to modify the label `api.openshift.com/image-type`.
Input:
```
object:
  metadata:
    labels:
      api.openshift.com/image-type: windows
oldObject:
  metadata:
    labels:
      api.openshift.com/image-type: linux
```

Expected Output:
```
false  (deny)
```

### Case 4 - Users should be allowed to modify labels other than `api.openshift.com/image-type`.
Input:
```
object:
  metadata:
    labels:
      api.openshift.com/other: 1
oldObject:
  metadata:
    labels:
      api.openshift.com/other: 2
```

Expected Output:
```
true   (allow)
```
