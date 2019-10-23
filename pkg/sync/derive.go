package sync

import (
	"github.com/openshift/managed-cluster-config/pkg/static/html"
)

type derivedType struct{}

var derived = &derivedType{}

func (derivedType) OAuthTemplateErrors() ([]byte, error) {
	return html.Asset("errors.html")
}

func (derivedType) OAuthTemplateLogin() ([]byte, error) {
	return html.Asset("login.html")
}

func (derivedType) OAuthTemplateProviders() ([]byte, error) {
	return html.Asset("providers.html")
}
