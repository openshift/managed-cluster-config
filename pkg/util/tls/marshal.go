package tls

import (
	"bytes"
	"crypto/rsa"
	"crypto/x509"
	"encoding/base64"
	"encoding/pem"
	"errors"
	"fmt"

	"golang.org/x/crypto/ssh"
)

func CertAsBytes(certs ...*x509.Certificate) (b []byte, err error) {
	defer func() {
		if r := recover(); r != nil {
			b, err = nil, fmt.Errorf("%v", r)
		}
	}()

	buf := &bytes.Buffer{}
	for _, cert := range certs {
		err = pem.Encode(buf, &pem.Block{Type: "CERTIFICATE", Bytes: cert.Raw})
		if err != nil {
			return nil, err
		}
	}

	return buf.Bytes(), nil
}

func CertChainAsBytes(certs []*x509.Certificate) (b []byte, err error) {
	return CertAsBytes(certs...)
}

func PrivateKeyAsBytes(key *rsa.PrivateKey) (b []byte, err error) {
	defer func() {
		if r := recover(); r != nil {
			b, err = nil, fmt.Errorf("%v", r)
		}
	}()

	buf := &bytes.Buffer{}

	err = pem.Encode(buf, &pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(key)})
	if err != nil {
		return nil, err
	}

	return buf.Bytes(), nil
}

func PublicKeyAsBytes(key *rsa.PublicKey) (b []byte, err error) {
	defer func() {
		if r := recover(); r != nil {
			b, err = nil, fmt.Errorf("%v", r)
		}
	}()

	buf := &bytes.Buffer{}

	b, err = x509.MarshalPKIXPublicKey(key)
	if err != nil {
		return nil, err
	}

	err = pem.Encode(buf, &pem.Block{Type: "PUBLIC KEY", Bytes: b})
	if err != nil {
		return nil, err
	}

	return buf.Bytes(), nil
}

func SSHPublicKeyAsString(key *rsa.PublicKey) (s string, err error) {
	defer func() {
		if r := recover(); r != nil {
			s, err = "", fmt.Errorf("%v", r)
		}
	}()

	sshkey, err := ssh.NewPublicKey(key)
	if err != nil {
		return "", err
	}

	return sshkey.Type() + " " + base64.StdEncoding.EncodeToString(sshkey.Marshal()), nil
}

// ParseCert takes certificate as bytes and returns x509.Certificate
func ParseCert(b []byte) (*x509.Certificate, error) {
	certs, err := ParseCertChain(b)
	if err != nil {
		return nil, err
	}
	if len(certs) > 0 {
		return certs[0], nil
	}
	return nil, errors.New("failed to parse certificate")
}

// ParseCertChain takes certificate as bytes and returns slice of all x509.Certificate
func ParseCertChain(b []byte) ([]*x509.Certificate, error) {
	var bundle []*x509.Certificate
	for {
		var block *pem.Block
		block, b = pem.Decode(b)
		if block == nil {
			break
		}

		switch block.Type {
		case "CERTIFICATE":
			cert, err := x509.ParseCertificate(block.Bytes)
			if err != nil {
				return nil, errors.New("failed to parse certificate")
			}
			bundle = append(bundle, cert)
		}
	}
	return bundle, nil
}

func ParsePrivateKey(b []byte) (*rsa.PrivateKey, error) {
	for {
		var block *pem.Block
		block, b = pem.Decode(b)
		if block == nil {
			break
		}

		switch block.Type {
		case "RSA PRIVATE KEY":
			return x509.ParsePKCS1PrivateKey(block.Bytes)

		case "PRIVATE KEY":
			if key, err := x509.ParsePKCS8PrivateKey(block.Bytes); err == nil {
				switch key := key.(type) {
				case *rsa.PrivateKey:
					return key, nil
				default:
					return nil, errors.New("found unknown private key type in PKCS#8 wrapping")
				}
			}
		}
	}

	return nil, errors.New("failed to parse private key")
}

// UniqueCert takes slice of the certificate and
// returns certificate slice with unique values
func UniqueCert(certs []*x509.Certificate) []*x509.Certificate {
	var uniqueCerts []*x509.Certificate
	seen := make(map[string]struct{}, len(certs))
	for _, v := range certs {
		if _, ok := seen[string(v.Raw)]; ok {
			continue
		}
		seen[string(v.Raw)] = struct{}{}
		uniqueCerts = append(uniqueCerts, v)
	}
	return uniqueCerts
}
