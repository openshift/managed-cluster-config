# IDS tester 
This project runs basic IDS tests by mimicking suspicious network traffic. Intended for use with openshift-suricata rules as it should log the connection attempts made by this project.

### Permissions 
This project runs as CronJob in the openshift-suricata namespace, and requires no elevated permissions.
