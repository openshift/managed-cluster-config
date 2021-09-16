# How to use the generate-add-ons-list.py script

The script uses python3. Make sure it is installed in your environment.

The script generates a YAML document created by default in managed-cluster-config/resources/addons-namespaces/main.yaml listing all namespaces created via addons that can be found here https://gitlab.cee.redhat.com/service/managed-tenants/-/tree/main/addons

With the managed-cluster-config repository and the managed-tenants repository cloned this is the way to run the script to generate a yaml listing all namespaces created via addons and save it as managed-cluster-config/resources/addons-namespaces/main.yaml  
```
python3 managed-cluster-config/scripts/addons-namespaces/script.py -p managed-tenants/addons/

```

If you would like the yaml file to be outputted somewhere else, this can be done with the  -o option as follows.

```
python3 managed-cluster-config/scripts/addons-namespaces/script.py -p managed-tenants/addons/ -o addons-namespaces-list.yaml

```