package config

import (
	"crypto/x509"
	"io/ioutil"

	"github.com/kelseyhightower/envconfig"
	"github.com/sirupsen/logrus"

	"github.com/openshift/managed-cluster-config/pkg/util/tls"
)

// Certificate is an x509 certificate.
type Certificate struct {
	Cert *x509.Certificate `json:"cert,omitempty"`
}

// Config contains all env based configurations to configure template
// TODO: Add  required:"true" tags
type Config struct {
	ImageTag           string `envconfig:"IMAGE_TAG" required:"true"`
	RepoName           string `envconfig:"REPO_NAME" required:"true"`
	TelemeterServerURL string `envconfig:"TELEMETER_SERVER_URL" required:"true"`

	// identity provider config
	IdentityAttrEmail             string `envconfig:"IDENTITY_ATTR_EMAIL" required:"true"`
	IdentityAttrID                string `envconfig:"IDENTITY_ATTR_ID" required:"true"`
	IdentityAttrName              string `envconfig:"IDENTITY_ATTR_NAME" required:"true"`
	IdentityAttrPreferredUsername string `envconfig:"IDENTITY_ATTR_PREFERRED_USERNAME" required:"true"`
	IdentityBindName              string `envconfig:"IDENTITY_BIND_DN" required:"true"`
	IdentityURL                   string `envconfig:"IDENTITY_URL" required:"true"`
	IdentityName                  string `envconfig:"IDENTITY_NAME" required:"true"`
	IdentityMappingMethod         string `envconfig:"IDENTITY_MAPPING_METHOD" required:"true"`

	// other configuration values
	OSDLdapCA           Certificate
	ValeroOperatorImage string `envconfig:"VALERO_OPERATOR_IMAGE"`
}

// NewConfig parses env variables and sets configuration
func NewConfig(log *logrus.Entry) (*Config, error) {
	var c Config
	if err := envconfig.Process("", &c); err != nil {
		return nil, err
	}

	// enrich template with secrets
	var err error
	c.OSDLdapCA.Cert, err = readCert("secrets/osd-ldap-ca.cert")
	if err != nil {
		return nil, err
	}

	return &c, nil
}

func readCert(path string) (*x509.Certificate, error) {
	b, err := ioutil.ReadFile(path)
	if err != nil {
		return nil, err
	}
	return tls.ParseCert(b)
}
