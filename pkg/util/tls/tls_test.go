package tls

import (
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"io/ioutil"
	"net"
	"os"
	"reflect"
	"testing"
	"time"
)

const (
	updateSSLVar = "UPDATE_KNOWN_SSL_CERT"
)

func readCert(path string) (*x509.Certificate, error) {
	b, err := ioutil.ReadFile(path)
	if err != nil {
		return nil, err
	}

	return ParseCert(b)
}

func writeCert(path string, cert *x509.Certificate) error {
	b, err := CertAsBytes(cert)
	if err != nil {
		return err
	}

	return ioutil.WriteFile(path, b, 0666)
}

func TestNewPrivateKey(t *testing.T) {
	key, err := NewPrivateKey()
	if err != nil {
		t.Error(err)
	}
	if key.Validate() != nil {
		t.Error(err)
	}
	if key.N.BitLen() < 2048 {
		t.Errorf("insecure key length detected: %d", key.N.BitLen())
	}
}

func TestNewCA(t *testing.T) {
	path := "./testdata/known_good_certCA.pem"

	key, cert, err := NewCA("dummy-test-certificate.local")
	if err != nil {
		t.Fatal(err)
	}
	err = key.Validate()
	if err != nil {
		t.Error(err)
	}
	if os.Getenv(updateSSLVar) == "true" {
		err = writeCert(path, cert)
		if err != nil {
			t.Error(err)
		}
	}
	goodCert, err := readCert(path)
	if err != nil {
		t.Fatal(err)
	}

	for _, c := range []*x509.Certificate{cert, goodCert} {
		c.NotBefore = time.Time{}
		c.NotAfter = time.Time{}
		c.PublicKey.(*rsa.PublicKey).N = nil
		c.Raw = nil
		c.RawSubjectPublicKeyInfo = nil
		c.RawTBSCertificate = nil
		c.SerialNumber = nil
		c.Signature = nil
	}

	if !reflect.DeepEqual(cert, goodCert) {
		t.Error("certificates did not match, check test for details")
	}
}

func TestNewCert(t *testing.T) {
	path := "testdata/known_good_cert.pem"

	cn := "dummy-test-certificate.local"
	key, cert, err := NewCert(&CertParams{
		Subject: pkix.Name{
			CommonName:   cn,
			Organization: []string{cn},
		},
		DNSNames:    []string{cn},
		IPAddresses: []net.IP{net.ParseIP("192.168.0.1")},
		ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth | x509.ExtKeyUsageClientAuth},
	})
	if err != nil {
		t.Fatal(err)
	}

	err = key.Validate()
	if err != nil {
		t.Error(err)
	}

	if os.Getenv(updateSSLVar) == "true" {
		err = writeCert(path, cert)
		if err != nil {
			t.Error(err)
		}
	}

	goodCert, err := readCert(path)
	if err != nil {
		t.Fatal(err)
	}

	for _, c := range []*x509.Certificate{cert, goodCert} {
		c.NotBefore = time.Time{}
		c.NotAfter = time.Time{}
		c.PublicKey.(*rsa.PublicKey).N = nil
		c.Raw = nil
		c.RawSubjectPublicKeyInfo = nil
		c.RawTBSCertificate = nil
		c.SerialNumber = nil
		c.Signature = nil
	}

	if !reflect.DeepEqual(cert, goodCert) {
		t.Error("certificates did not match, check test for details")
	}
}

func TestSignedCertificate(t *testing.T) {
	cn := "dummy-test-certificate.local"

	signingKey, signingCA, err := NewCA("dummy-test-certificate.local")
	if err != nil {
		t.Error(err)
	}
	_, cert, err := NewCert(&CertParams{
		Subject: pkix.Name{
			CommonName:   cn,
			Organization: []string{cn},
		},
		DNSNames:    []string{cn},
		IPAddresses: []net.IP{net.ParseIP("192.168.0.1")},
		ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth | x509.ExtKeyUsageClientAuth},
		SigningKey:  signingKey,
		SigningCert: signingCA,
	})
	if err != nil {
		t.Error(err)
	}
	roots := x509.NewCertPool()
	roots.AddCert(signingCA)
	keyUsages := []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth | x509.ExtKeyUsageClientAuth}
	opts := x509.VerifyOptions{
		DNSName:   cn,
		Roots:     roots,
		KeyUsages: keyUsages,
	}
	if _, err := cert.Verify(opts); err != nil {
		t.Error(err)
	}
}

func TestCertMatchesParams(t *testing.T) {
	if CertMatchesParams(nil, &x509.Certificate{}, &CertParams{}) {
		t.Error("should return false when key is nil")
	}
	if CertMatchesParams(&rsa.PrivateKey{}, nil, &CertParams{}) {
		t.Error("should return false when cert is nil")
	}

	caKey, caCert, err := NewCA("test-ca")
	if err != nil {
		t.Fatal(err)
	}
	privateKey, err := NewPrivateKey()
	if err != nil {
		t.Fatal(err)
	}

	selfSignedParams := &CertParams{
		Subject: pkix.Name{
			CommonName:   "test",
			Organization: []string{"test"},
		},
		DNSNames:    []string{"test"},
		IPAddresses: []net.IP{net.ParseIP("192.168.0.1")},
		ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth | x509.ExtKeyUsageClientAuth},
	}
	selfSignedKey, selfSignedCert, err := NewCert(selfSignedParams)
	if err != nil {
		t.Fatal(err)
	}

	signedParams := &CertParams{
		Subject: pkix.Name{
			CommonName:   "test",
			Organization: []string{"test"},
		},
		DNSNames:    []string{"test"},
		IPAddresses: []net.IP{net.ParseIP("192.168.0.1")},
		ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth | x509.ExtKeyUsageClientAuth},
		SigningKey:  caKey,
		SigningCert: caCert,
	}
	signedKey, signedCert, err := NewCert(signedParams)
	if err != nil {
		t.Fatal(err)
	}

	for _, suite := range []struct {
		name   string
		key    *rsa.PrivateKey
		cert   *x509.Certificate
		params *CertParams
	}{
		{
			name:   "self-signed",
			key:    selfSignedKey,
			cert:   selfSignedCert,
			params: selfSignedParams,
		},
		{
			name:   "signed",
			key:    signedKey,
			cert:   signedCert,
			params: signedParams,
		},
	} {
		if !CertMatchesParams(suite.key, suite.cert, suite.params) {
			t.Errorf("%s: should return true immediately after calling NewCert", suite.name)
		}
		if CertMatchesParams(privateKey, suite.cert, suite.params) {
			t.Errorf("%s: should return false when private key doesn't match", suite.name)
		}

		tests := []struct {
			name    string
			mogrify func(*CertParams)
		}{
			{
				name:    "common name changes",
				mogrify: func(params *CertParams) { params.Subject.CommonName = "new" },
			},
			{
				name:    "organization changes",
				mogrify: func(params *CertParams) { params.Subject.Organization = []string{"new"} },
			},
			{
				name:    "IPAddresses changes",
				mogrify: func(params *CertParams) { params.IPAddresses = []net.IP{net.ParseIP("192.168.0.2")} },
			},
			{
				name:    "DNSNames changes",
				mogrify: func(params *CertParams) { params.DNSNames = []string{"new"} },
			},
			{
				name:    "ExtKeyUsage changes",
				mogrify: func(params *CertParams) { params.ExtKeyUsage = []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth} },
			},
			{
				name: "SigningCert changes",
				mogrify: func(params *CertParams) {
					// this tests changing the CA cert, or changing a
					// self-signed cert to a CA-signed cert
					params.SigningKey, params.SigningCert, err = NewCA("test-ca")
					if err != nil {
						t.Fatal(err)
					}
				},
			},
		}

		for _, test := range tests {
			params := *suite.params
			test.mogrify(&params)
			if CertMatchesParams(suite.key, suite.cert, &params) {
				t.Errorf("%s: test %q failed", suite.name, test.name)
			}
		}
	}

	{
		// this tests changing a CA-signed cert to a self-signed cert
		params := *signedParams
		params.SigningKey, params.SigningCert = nil, nil
		if CertMatchesParams(signedKey, signedCert, &params) {
			t.Error("should return false on signed cert when going to self-signed")
		}
	}
}
