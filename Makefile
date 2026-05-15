SHELL=/bin/bash
BUILD_CONFIG ?= images.yaml
# DOCKER_REGISTRY ?= $(shell cat $(BUILD_CONFIG)| yq -r .prefix)
DOCKER_REGISTRY ?= tgagor/dhi
GIT_COMMIT ?= $(shell git rev-parse HEAD)
GIT_BRANCH ?= $(shell git rev-parse --abbrev-ref HEAD)
GIT_URL ?= $(shell git config --get remote.origin.url)
GIT_TAG ?= $(shell echo $(GIT_BRANCH) | sed -E 's/[/:]/-/g' | sed 's/main/latest/' )
DHICTL ?= docker dhi
DHI_REPO_URL ?= https://raw.githubusercontent.com/docker-hardened-images/catalog/refs/heads/main/image/
# MAINTAINER ?= $(shell cat $(BUILD_CONFIG)| yq -r '.maintainer')
IMAGES := $(shell cat $(BUILD_CONFIG) | yq -r '.images|keys[]')
ALL_COMBINATIONS := $(shell cat $(BUILD_CONFIG) | yq -r '.images | to_entries | .[] | .key as $$image | .value.os[] as $$os | .value.variants[] as $$variant | "\($$image),\($$os),\($$variant)"')
DHICTL_VERSION ?= latest

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Linux)
	OS_NAME += linux
endif
ifeq ($(UNAME_S),Darwin)
	OS_NAME += darwin
endif
UNAME_M := $(shell uname -m)
ifeq ($(UNAME_M),x86_64)
	OS_ARCH += amd64
endif
ifneq ($(filter arm%,$(UNAME_M)),)
	OS_ARCH += arm64
endif


.PHONY: all build push summary clean build-image build-combination-% $(IMAGES)

all: summary


install-dhictl:
	@echo "Installing dhictl plugin for Docker CLI"

	mkdir -p ~/.docker/cli-plugins
	curl -sLfo ~/.docker/cli-plugins/docker-dhi https://github.com/docker-hardened-images/dhictl/releases/${DHICTL_VERSION}/download/dhictl-${OS_NAME}-${OS_ARCH}
	chmod +x ~/.docker/cli-plugins/docker-dhi
	$(DHICTL) --version

list-images:
	@echo "Configured images to build:"
	@echo "$(ALL_COMBINATIONS)"

build-image:
	$(call stage_status,build-image: $(IMAGE)/$(OS)/$(VARIANT))
	@{ \
		IMAGE_URL=$(DHI_REPO_URL)$(IMAGE)/$(OS)/$(VARIANT).yaml; \
		IMAGE_TAGS=$$(curl -s "$$IMAGE_URL" | yq -r '.tags[]' | sed 's|^|--tag $(DOCKER_REGISTRY)/$(IMAGE):|' | tr '\n' ' '); \
		docker buildx build \
			$$IMAGE_URL \
			--sbom=generator=dhi.io/scout-sbom-indexer:1 \
			--provenance=1 \
			--tag $(DOCKER_REGISTRY)/$(IMAGE):$(GIT_TAG) \
			$$IMAGE_TAGS \
			--load; \
	}

$(addprefix build-combination-,$(ALL_COMBINATIONS)): build-combination-%:
	@IMAGE_NAME=$$(echo '$*' | cut -d, -f1); \
	IMAGE_OS=$$(echo '$*' | cut -d, -f2); \
	IMAGE_VARIANT=$$(echo '$*' | cut -d, -f3); \
	$(MAKE) build-image IMAGE=$$IMAGE_NAME OS=$$IMAGE_OS VARIANT=$$IMAGE_VARIANT

build: $(addprefix build-combination-,$(ALL_COMBINATIONS))
	$(call stage_status,build)


define stage_status
	@echo
	@echo
	@echo ================================================================================
	@echo Building: $(1)
	@echo ================================================================================
endef

define summary
	@echo
	@echo
	@echo ================================================================================
	@echo Generated images:
	@echo ================================================================================
	@docker image ls \
		--format "{{.Repository}}:{{.Tag}}\t{{.Size}}" \
		--filter=dangling=false \
		--filter=reference="$(DOCKER_REGISTRY)/*:*" | sort | column -t
endef


clean:
	@docker image rm -f $(shell docker image ls --format "{{.Repository}}:{{.Tag}}" --filter=dangling=false --filter=reference="$(DOCKER_REGISTRY)/*:*") 2>/dev/null || true

prune:
	@docker system prune --all --force --volumes
	@docker buildx prune --all --force

summary:
	$(call summary)
