package template

import (
	"bytes"
	"encoding/base64"
	"encoding/xml"
	"strconv"
	"strings"
	"text/template"

	"github.com/ghodss/yaml"

	"github.com/openshift/managed-cluster-config/pkg/util/tls"
)

func Template(name, tmpl string, f template.FuncMap, data interface{}) ([]byte, error) {
	t, err := template.New(name).Funcs(template.FuncMap{
		"CertAsBytes":       tls.CertAsBytes,
		"CertChainAsBytes":  tls.CertChainAsBytes,
		"PrivateKeyAsBytes": tls.PrivateKeyAsBytes,
		"PublicKeyAsBytes":  tls.PublicKeyAsBytes,
		"YamlMarshal":       yaml.Marshal,
		"Base64Encode":      base64.StdEncoding.EncodeToString,
		"String":            func(b []byte) string { return string(b) },
		"quote":             strconv.Quote,
		"ImageOnly":         func(s string) string { return strings.Split(s, ":")[0] },
		"escape": func(b string) string {
			replacer := strings.NewReplacer("$", "\\$")
			return replacer.Replace(b)
		},
		"StringsJoin": strings.Join,
		"XMLEscape": func(s string) (string, error) {
			var b bytes.Buffer
			err := xml.EscapeText(&b, []byte(s))
			return b.String(), err
		},
	}).Funcs(f).Parse(tmpl)
	if err != nil {
		return nil, err
	}

	b := &bytes.Buffer{}

	err = t.Execute(b, data)
	if err != nil {
		return nil, err
	}

	return b.Bytes(), nil
}
