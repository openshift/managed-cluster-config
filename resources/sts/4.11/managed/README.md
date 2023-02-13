# Managed STS roles policies

This directory contains AWS IAM policies that are designed to restrict IAM actions to resources where the AWS tag `red-hat-managed=true` is present. These policies allow tags to be added to resources in AWS provided the tags are passed as part of the create API call to AWS. 

To see what AWS actions support condition keys (used to restrict actions by tag) can be found [here](https://docs.aws.amazon.com/service-authorization/latest/reference/reference.html).

The policies in this directory are under review and should not be used for production environments until [SDE-1703](https://issues.redhat.com/browse/SDE-1703) is complete.
