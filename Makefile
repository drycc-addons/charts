SHELL := /bin/bash

DRYCC_REGISTRY ?= registry.drycc.cc
REGISTRY ?= $(DRYCC_REGISTRY)

CHART_VERSION ?= 1.0.0
APP_VERSION ?= $(shell git rev-parse --short HEAD)

.PHONY: build push clean lint

check-helm:
	@if [ -z $$(which helm) ]; then \
	  echo "helm binary could not be located"; \
	  exit 2; \
	fi

build: check-helm
	_scripts/build-charts.sh

push: build
	@_scripts/push-charts.sh $(REGISTRY)

clean:
	rm -rf _dist/*.tgz

lint:
	@find addons classes -name '*.yaml' -not -path '*/crds/*' \
	  | xargs -I {} helm lint {} 2>&1 \
	  || true
