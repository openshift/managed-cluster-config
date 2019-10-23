package tls

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"math/big"
	"net"
	"reflect"
	"time"
)

// NewPrivateKey returns a new 2048-bit rsa.PrivateKey
func NewPrivateKey() (*rsa.PrivateKey, error) {
	return rsa.GenerateKey(rand.Reader, 2048)
}

func newCert(key *rsa.PrivateKey, template *x509.Certificate, signingkey *rsa.PrivateKey, signingcert *x509.Certificate) (*x509.Certificate, error) {
	if signingcert == nil && signingkey == nil {
		// make it self-signed
		signingcert = template
		signingkey = key
	}

	b, err := x509.CreateCertificate(rand.Reader, template, signingcert, key.Public(), signingkey)
	if err != nil {
		return nil, err
	}

	return x509.ParseCertificate(b)
}

// NewCA returns a new rsa.PrivateKey and x509.Certificate for a CA
// corresponding to the given CommonName.
func NewCA(cn string) (*rsa.PrivateKey, *x509.Certificate, error) {
	now := time.Now().Add(-time.Hour)

	serialNumber, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	if err != nil {
		return nil, nil, err
	}

	template := &x509.Certificate{
		SerialNumber:          serialNumber,
		NotBefore:             now,
		NotAfter:              now.AddDate(5, 0, 0),
		Subject:               pkix.Name{CommonName: cn},
		BasicConstraintsValid: true,
		KeyUsage:              x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment | x509.KeyUsageCertSign,
		IsCA:                  true,
	}

	key, err := NewPrivateKey()
	if err != nil {
		return nil, nil, err
	}

	cert, err := newCert(key, template, nil, nil)
	if err != nil {
		return nil, nil, err
	}

	return key, cert, nil
}

// CertParams defines the parameters which can be passed into NewCert.
type CertParams struct {
	Subject     pkix.Name
	DNSNames    []string
	IPAddresses []net.IP
	ExtKeyUsage []x509.ExtKeyUsage
	SigningKey  *rsa.PrivateKey   // leave nil for self-signed
	SigningCert *x509.Certificate // leave nil for self-signed
}

// NewCert returns a new rsa.PrivateKey and x509.Certificate for a certificate
// corresponding to the given CertParams struct.
func NewCert(p *CertParams) (*rsa.PrivateKey, *x509.Certificate, error) {
	now := time.Now()

	serialNumber, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	if err != nil {
		return nil, nil, err
	}

	template := &x509.Certificate{
		SerialNumber:          serialNumber,
		NotBefore:             now,
		NotAfter:              now.AddDate(2, 0, 0),
		Subject:               p.Subject,
		BasicConstraintsValid: true,
		KeyUsage:              x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
		ExtKeyUsage:           p.ExtKeyUsage,
		DNSNames:              p.DNSNames,
		IPAddresses:           p.IPAddresses,
	}

	key, err := NewPrivateKey()
	if err != nil {
		return nil, nil, err
	}
	cert, err := newCert(key, template, p.SigningKey, p.SigningCert)
	if err != nil {
		return nil, nil, err
	}

	return key, cert, nil
}

// CertMatchesParams returns true if the given key and cert match the CertParams
// struct.
func CertMatchesParams(key *rsa.PrivateKey, cert *x509.Certificate, params *CertParams) bool {
	if key == nil || cert == nil {
		return false
	}

	// check the key and cert match eachother
	certPublicKey, ok := cert.PublicKey.(*rsa.PublicKey)
	if !ok || !reflect.DeepEqual(key.PublicKey, *certPublicKey) {
		return false
	}

	// check the relevant cert fields match the params struct
	if !reflect.DeepEqual(cert.Subject.ToRDNSequence(), params.Subject.ToRDNSequence()) ||
		!reflect.DeepEqual(cert.DNSNames, params.DNSNames) ||
		!netIPsEqual(cert.IPAddresses, params.IPAddresses) ||
		!reflect.DeepEqual(cert.ExtKeyUsage, params.ExtKeyUsage) {
		return false
	}

	if params.SigningCert != nil {
		// check the cert signed by the signingCert
		if cert.CheckSignatureFrom(params.SigningCert) != nil {
			return false
		}
	} else {
		// check the cert is self-signed
		if cert.CheckSignature(cert.SignatureAlgorithm, cert.RawTBSCertificate, cert.Signature) != nil {
			return false
		}
	}

	return true
}

func netIPsEqual(ip1, ip2 []net.IP) bool {
	// reflect.DeepEqual doesn't work on net.IP - see net.IP.Equal() for details
	if len(ip1) != len(ip2) {
		return false
	}
	for i := range ip1 {
		if !ip1[i].Equal(ip2[i]) {
			return false
		}
	}
	return true
}
