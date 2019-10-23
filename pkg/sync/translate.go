package sync

import (
	"encoding/base64"
	"fmt"

	"github.com/ghodss/yaml"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"

	"github.com/openshift/managed-cluster-config/pkg/config"
	"github.com/openshift/managed-cluster-config/pkg/util/jsonpath"
	util "github.com/openshift/managed-cluster-config/pkg/util/template"
)

func keyFunc(gk schema.GroupKind, namespace, name string) string {
	s := gk.String()
	if namespace != "" {
		s += "/" + namespace
	}
	s += "/" + name

	return s
}

type nestedFlags int

const (
	nestedFlagsBase64 nestedFlags = (1 << iota)
)

func translateAsset(o unstructured.Unstructured, config *config.Config) (unstructured.Unstructured, error) {
	ts := translations[keyFunc(o.GroupVersionKind().GroupKind(), o.GetNamespace(), o.GetName())]
	for i, tr := range ts {
		var s interface{}
		if tr.F != nil {
			var err error
			s, err = tr.F(o.Object)
			if err != nil {
				return unstructured.Unstructured{}, err
			}
		} else {
			b, err := util.Template(fmt.Sprintf("%s/%d", keyFunc(o.GroupVersionKind().GroupKind(), o.GetNamespace(), o.GetName()), i), tr.Template, nil, map[string]interface{}{
				"Config":  config,
				"Derived": derived,
			})
			s = string(b)
			if err != nil {
				return unstructured.Unstructured{}, err
			}
		}

		err := translate(o.Object, tr.Path, tr.NestedPath, tr.nestedFlags, s)
		if err != nil {
			return unstructured.Unstructured{}, err
		}

	}
	return o, nil
}

func translate(o interface{}, path jsonpath.Path, nestedPath jsonpath.Path, nestedFlags nestedFlags, v interface{}) error {
	var err error

	if nestedPath == nil {
		path.Set(o, v)
		return nil
	}

	nestedBytes := []byte(path.MustGetString(o))

	if nestedFlags&nestedFlagsBase64 != 0 {
		nestedBytes, err = base64.StdEncoding.DecodeString(string(nestedBytes))
		if err != nil {
			return err
		}
	}

	var nestedObject interface{}
	err = yaml.Unmarshal(nestedBytes, &nestedObject)
	if err != nil {
		panic(err)
	}

	nestedPath.Set(nestedObject, v)

	nestedBytes, err = yaml.Marshal(nestedObject)
	if err != nil {
		panic(err)
	}

	if nestedFlags&nestedFlagsBase64 != 0 {
		nestedBytes = []byte(base64.StdEncoding.EncodeToString(nestedBytes))
		if err != nil {
			panic(err)
		}
	}

	path.Set(o, string(nestedBytes))

	return nil
}

var translations = map[string][]struct {
	Path        jsonpath.Path
	NestedPath  jsonpath.Path
	nestedFlags nestedFlags
	Template    string
	F           func(interface{}) (interface{}, error)
}{
	// IMPORTANT: translations must NOT use the quote function (i.e., write
	// "{{ .Config.Foo }}", NOT "{{ .Config.Foo | quote }}").  This is because
	// the translations operate on in-memory objects, not on serialised YAML.
	// Correct quoting will be handled automatically by the marshaller.
	"ConfigMap/openshift-config/osd-ldap-ca-configmap": {
		{
			Path:     jsonpath.MustCompile("$.stringData.ca.crt"),
			Template: "{{ Base64Encode (CertAsBytes .Config.OSDLdapCA.Cert) }}",
		},
	},
	"ConfigMap/openshift-monitoring/cluster-monitoring-config": {
		{
			Path:       jsonpath.MustCompile("$.data.'config.yaml'"),
			NestedPath: jsonpath.MustCompile("$.telemeterClient.telemeterServerURL"),
			Template:   "{{ .Config.TelemeterServerURL }}",
		},
	},
	"Deployment.apps/openshift-valero/managed-valero-operator": {
		{
			Path:     jsonpath.MustCompile("$.spec.template.spec.containers[0].image'"),
			Template: "{{ .Config.ValeroOperatorImage }}",
		},
	},
	"Secret/openshift-config/osd-oauth-templates-errors": {
		{
			Path:     jsonpath.MustCompile("$.stringData.'errors.html'"),
			Template: "{{ Base64Encode .Derived.OAuthTemplateErrors }}",
		},
	},
	"Secret/openshift-config/osd-oauth-templates-login": {
		{
			Path:     jsonpath.MustCompile("$.stringData.'login.html'"),
			Template: "{{ Base64Encode .Derived.OAuthTemplateLogin }}",
		},
	},
	"Secret/openshift-config/osd-oauth-templates-providers": {
		{
			Path:     jsonpath.MustCompile("$.stringData.'providers.html'"),
			Template: "{{ Base64Encode .Derived.OAuthTemplateLogin }}",
		},
	},
	"SelectorSyncIdentityProvider.hive.openshift.io/osd-sre-identityprovider": {
		{
			Path:     jsonpath.MustCompile("$.metadata.labels['managed.openshift.io/gitHash']"),
			Template: "{{ .Config.ImageTag }}",
		},
		{
			Path:     jsonpath.MustCompile("$.metadata.labels['managed.openshift.io/gitRepoName']"),
			Template: "{{ .Config.RepoName }}",
		},
		{
			Path:     jsonpath.MustCompile("$.spec.identityProviders[0].ldap.attributes.email[0]"),
			Template: "{{ .Config.IdentityAttrEmail }}",
		},
		{
			Path:     jsonpath.MustCompile("$.spec.identityProviders[0].ldap.attributes.id[0]"),
			Template: "{{ .Config.IdentityAttrID }}",
		},
		{
			Path:     jsonpath.MustCompile("$.spec.identityProviders[0].ldap.attributes.name[0]"),
			Template: "{{ .Config.IdentityAttrName }}",
		},
		{
			Path:     jsonpath.MustCompile("$.spec.identityProviders[0].ldap.attributes.preferredUsername[0]"),
			Template: "{{ .Config.IdentityAttrPreferredUsername }}",
		},
		{
			Path:     jsonpath.MustCompile("$.spec.identityProviders[0].ldap.bindDN"),
			Template: "{{ .Config.IdentityBindName }}",
		},
		{
			Path:     jsonpath.MustCompile("$.spec.identityProviders[0].ldap.url"),
			Template: "{{ .Config.IdentityURL }}",
		},
		{
			Path:     jsonpath.MustCompile("$.spec.identityProviders[0].mappingMethod"),
			Template: "{{ .Config.IdentityMappingMethod }}",
		},
		{
			Path:     jsonpath.MustCompile("$.spec.identityProviders[0].name"),
			Template: "{{ .Config.IdentityName }}",
		},
	},
	"SelectorSyncSet.hive.openshift.io/kubelet-config": {
		{
			Path:     jsonpath.MustCompile("$.metadata.labels['managed.openshift.io/gitHash']"),
			Template: "{{ .Config.ImageTag }}",
		},
		{
			Path:     jsonpath.MustCompile("$.metadata.labels['managed.openshift.io/gitRepoName']"),
			Template: "{{ .Config.RepoName }}",
		},
	},
	"SelectorSyncSet.hive.openshift.io/osd-curated-operators": {
		{
			Path:     jsonpath.MustCompile("$.metadata.labels['managed.openshift.io/gitHash']"),
			Template: "{{ .Config.ImageTag }}",
		},
		{
			Path:     jsonpath.MustCompile("$.metadata.labels['managed.openshift.io/gitRepoName']"),
			Template: "{{ .Config.RepoName }}",
		},
	},
	"SelectorSyncSet.hive.openshift.io/osd-oauth-templates": {
		{
			Path:     jsonpath.MustCompile("$.metadata.labels['managed.openshift.io/gitHash']"),
			Template: "{{ .Config.ImageTag }}",
		},
		{
			Path:     jsonpath.MustCompile("$.metadata.labels['managed.openshift.io/gitRepoName']"),
			Template: "{{ .Config.RepoName }}",
		},
	},
	"SelectorSyncSet.hive.openshift.io/osd-registry": {
		{
			Path:     jsonpath.MustCompile("$.metadata.labels['managed.openshift.io/gitHash']"),
			Template: "{{ .Config.ImageTag }}",
		},
		{
			Path:     jsonpath.MustCompile("$.metadata.labels['managed.openshift.io/gitRepoName']"),
			Template: "{{ .Config.RepoName }}",
		},
	},
	"SelectorSyncSet.hive.openshift.io/resource-quotas": {
		{
			Path:     jsonpath.MustCompile("$.metadata.labels['managed.openshift.io/gitHash']"),
			Template: "{{ .Config.ImageTag }}",
		},
		{
			Path:     jsonpath.MustCompile("$.metadata.labels['managed.openshift.io/gitRepoName']"),
			Template: "{{ .Config.RepoName }}",
		},
	},
}
