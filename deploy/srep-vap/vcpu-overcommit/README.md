# Validating Admission Policy to restrict Windows VM for overcommiting vCPU 

Reference card: CNV-56734

## Test cases
We can use [CEL playground](https://playcel.undistro.io/) to experiment with the CEL used in the `ValidatingAdmissionPolicy`.

### Case 1 - Windows VM with a non-dedicated preference should be denied
Input:
```
object:
  metadata:
    annotations:
      kubevirt.io/preference-name: windows-server-2022
oldObject: {}
```

Expected Output:
```
false  (deny)
```

### Case 2 - Windows VM with a dedicated preference should be allowed
Input:
```
object:
  metadata:
    annotations:
      kubevirt.io/preference-name: windows-server-2022-dedicated
oldObject: {}
```

Expected Output:
```
true  (allow)
```

### Case 3 - Non-Windows VM should be allowed regardless of preference
Input:
```
object:
  metadata:
    annotations:
      kubevirt.io/preference-name: rocky-linux
oldObject: {}
```

Expected Output:
```
true  (allow)
```

### Case 4 - Windows VM with cluster preference not including 'dedicated' should be denied
Input:
```
object:
  metadata:
    annotations:
      kubevirt.io/cluster-preference-name: windows10
oldObject: {}
```

Expected Output:
```
false  (deny)
```

### Case 5 - Windows VM with cluster preference including 'dedicated' should be allowed
Input:
```
object:
  metadata:
    annotations:
      kubevirt.io/cluster-preference-name: windows10-dedicated
oldObject: {}
```

Expected Output:
```
true  (allow)
```

