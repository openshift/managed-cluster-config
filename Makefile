SHELL := /bin/bash
GITCOMMIT=$(shell git rev-parse --short HEAD)$(shell [[ $$(git status --porcelain) = "" ]] || echo -dirty)
LDFLAGS="-X main.gitCommit=$(GITCOMMIT)"
IMAGE ?= managed-cluster-config:$(GITCOMMIT)

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
	hack/verify/validate-generated.sh

.PHONY: build
build:
	go build -ldflags ${LDFLAGS} ./cmd/template/

.PHONY: image
image:
	podman image build -t ${IMAGE} --file=Dockerfile

.PHONY: run
run: clean generate build
	./template