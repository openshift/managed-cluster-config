module github.com/openshift/managed-cluster-config

go 1.12

// ping to 1.13 release
replace k8s.io/apimachinery => k8s.io/apimachinery v0.0.0-20190704094520-6f131bee5e2c

replace k8s.io/client-go => k8s.io/client-go v10.0.0+incompatible

replace k8s.io/api => k8s.io/api v0.0.0-20191004102255-dacd7df5a50b

replace github.com/openshift/cluster-network-operator => github.com/openshift/cluster-network-operator v0.0.0-20190207145423-c226dcab667e

require (
	github.com/ghodss/yaml v1.0.0
	github.com/go-bindata/go-bindata v3.1.2+incompatible // indirect
	github.com/gogo/protobuf v1.3.1 // indirect
	github.com/golang/glog v0.0.0-20160126235308-23def4e6c14b // indirect
	github.com/google/btree v1.0.0 // indirect
	github.com/google/go-cmp v0.3.1
	github.com/gregjones/httpcache v0.0.0-20190611155906-901d90724c79 // indirect
	github.com/json-iterator/go v1.1.7 // indirect
	github.com/kelseyhightower/envconfig v1.4.0
	github.com/openshift/api v3.9.1-0.20191022140146-7d6a73218cc4+incompatible // indirect
	github.com/openshift/cluster-network-operator v0.0.0-20190207145423-c226dcab667e // indirect
	github.com/openshift/hive v0.0.0-20191020035449-08ae9d507dad
	github.com/peterbourgon/diskv v2.0.1+incompatible // indirect
	github.com/sirupsen/logrus v1.4.2
	github.com/stretchr/testify v1.4.0 // indirect
	golang.org/x/crypto v0.0.0-20190617133340-57b3e21c3d56
	golang.org/x/net v0.0.0-20190827160401-ba9fcec4b297 // indirect
	golang.org/x/oauth2 v0.0.0-20190604053449-0f29369cfe45 // indirect
	golang.org/x/sync v0.0.0-20190423024810-112230192c58
	golang.org/x/time v0.0.0-20181108054448-85acf8d2951c // indirect
	golang.org/x/tools v0.0.0-20191022213345-0bbdf54effa2 // indirect
	google.golang.org/appengine v1.5.0 // indirect
	k8s.io/api v0.0.0-20191016225839-816a9b7df678
	k8s.io/apiextensions-apiserver v0.0.0-20191004105443-a7d558db75c6
	k8s.io/apimachinery v0.0.0-20191016225534-b1267f8c42b4
	k8s.io/client-go v10.0.0+incompatible
	k8s.io/kube-aggregator v0.0.0-20191004103911-2797d0dcf14b
	sigs.k8s.io/controller-runtime v0.3.0 // indirect
)
