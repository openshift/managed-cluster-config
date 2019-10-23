SHELL := /usr/bin/env bash

.PHONY: default
default: clean generate generate-syncset

.PHONY: generate-syncset
generate-syncset:
	go run cmd/template/main.go

.PHONY: clean
clean:
	rm -rf _data

.PHONY: generate
generate:
	go generate ./...

.PHONY: test
test:
	go test ./...

.PHONY: verify
verify:
	go run hack/validate-imports/validate-imports.go cmd hack pkg
	hack/verify/validate-code-format.sh 