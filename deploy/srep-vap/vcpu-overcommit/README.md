# Validating Admission Policy to restrict Windows VM for overcommiting vCPU 

Reference card: CNV-56734

## Test cases
We can use [CEL playground](https://playcel.undistro.io/) to experiment with the CEL used in the `ValidatingAdmissionPolicy`.

### Case 1 - Windows VMI without dedicatedCpuPlacement should be denied
Input:
```
object:
  metadata:
    annotations:
      vm.kubevirt.io/os: windows
  spec:
    domain:
      cpu:
        dedicatedCpuPlacement: false
oldObject: {}
```

Expected Output:
```
false  (deny)
```

### Case 2 - Windows VMI with dedicatedCpuPlacement should be allowed
Input:
```
object:
  metadata:
    annotations:
      vm.kubevirt.io/os: windows
  spec:
    domain:
      cpu:
        dedicatedCpuPlacement: true
oldObject: {}
```

Expected Output:
```
true  (allow)
```

### Case 3 - Windows VMI missing dedicatedCpuPlacement field should be denied
Input:
```
object:
  metadata:
    annotations:
      vm.kubevirt.io/os: windows
  spec:
    domain:
      cpu: {}
oldObject: {}
```

Expected Output:
```
false  (deny)
```

### Case 4 - Non-Windows VMI should be allowed
Input:
```
object:
  metadata:
    annotations:
      vm.kubevirt.io/os: linux
  spec:
    domain:
      cpu: {}
oldObject: {}
```

Expected Output:
```
true  (allow)
```
