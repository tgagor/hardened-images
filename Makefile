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

CUSTOMIZATIONS_CONFIG ?= customizations.yaml
ARTIFACTS := $(shell cat $(CUSTOMIZATIONS_CONFIG) | yq -r '.artifacts|keys[]' 2>/dev/null || echo '')
CUSTOMIZATION_REGISTRY ?= $(DOCKER_REGISTRY)

CUSTOMIZATION_SUFFIX ?= _custom

PLATFORMS ?= linux/amd64
# PLATFORMS ?= linux/amd64,linux/arm64

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


.PHONY: all build push summary clean build-image build-combination-% $(IMAGES) \
        list-customizations build-customizations push-customizations build-artifact-% push-artifact-% \
        build-customized-image build-customized-combination-% build-customized

all: build summary

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

install-dhictl:
	@echo "Installing dhictl plugin for Docker CLI"

	mkdir -p ~/.docker/cli-plugins
	curl -sLfo ~/.docker/cli-plugins/docker-dhi https://github.com/docker-hardened-images/dhictl/releases/${DHICTL_VERSION}/download/dhictl-${OS_NAME}-${OS_ARCH}
	chmod +x ~/.docker/cli-plugins/docker-dhi
	$(DHICTL) --version

list-images:
	@echo "Configured images to build:"
	@echo "$(ALL_COMBINATIONS)" | tr ' ' '\n' | sort

build-image:
	$(call stage_status,build-image: $(IMAGE)/$(OS)/$(VARIANT):$(GIT_TAG))
	@{ \
		IMAGE_URL=$(DHI_REPO_URL)$(IMAGE)/$(OS)/$(VARIANT).yaml; \
		IMAGE_TAGS=$$(curl -s "$$IMAGE_URL" | yq -r '.tags[]' | sed 's|^|--tag $(DOCKER_REGISTRY)/$(IMAGE):|' | tr '\n' ' '); \
		IMAGE_PLATFORMS=$$(cat $(BUILD_CONFIG) | yq -r '.images["$(IMAGE)"].platforms[]?' 2>/dev/null | tr '\n' ',' | sed 's/,$$//' ); \
		IMAGE_PLATFORMS=$${IMAGE_PLATFORMS:-$(PLATFORMS)}; \
		docker buildx build \
			--platform $$IMAGE_PLATFORMS \
			--sbom=generator=dhi.io/scout-sbom-indexer:1 \
			--provenance=1 \
			$$IMAGE_URL \
			--tag $(DOCKER_REGISTRY)/$(IMAGE):$(GIT_TAG)-$(VARIANT)-$(OS) \
			$$IMAGE_TAGS \
			--load; \
	}

$(addprefix build-combination-,$(ALL_COMBINATIONS)): build-combination-%:
	@IMAGE_NAME=$$(echo '$*' | cut -d, -f1); \
	IMAGE_OS=$$(echo '$*' | cut -d, -f2); \
	IMAGE_VARIANT=$$(echo '$*' | cut -d, -f3); \
	$(MAKE) build-image IMAGE=$$IMAGE_NAME OS=$$IMAGE_OS VARIANT=$$IMAGE_VARIANT

build: build-customizations $(addprefix build-combination-,$(ALL_COMBINATIONS)) build-customized
	$(call stage_status,build)

build-customized-image:
	$(call stage_status,build-customized-image: $(IMAGE)/$(OS)/$(VARIANT) with customizations)
	@TEMP_DIR=$$(mktemp -d); \
	IMAGE_PLATFORMS=$$(cat $(BUILD_CONFIG) | yq -r '.images["$(IMAGE)"].platforms[]?' 2>/dev/null | tr '\n' ',' | sed 's/,$$//' ); \
	IMAGE_PLATFORMS=$${IMAGE_PLATFORMS:-$(PLATFORMS)}; \
	\
	GLOBAL_CUSTOMIZATIONS=$$(cat $(BUILD_CONFIG) | yq -r '.global_customizations[]?.artifact' 2>/dev/null | tr '\n' ' '); \
	IMAGE_CUSTOMIZATIONS=$$(cat $(BUILD_CONFIG) | yq -r '.images["$(IMAGE)"].customizations[]?.artifact' 2>/dev/null | tr '\n' ' '); \
	ALL_CUSTOMIZATIONS="$$GLOBAL_CUSTOMIZATIONS $$IMAGE_CUSTOMIZATIONS"; \
	\
	if [ -z "$${ALL_CUSTOMIZATIONS// }" ]; then \
		echo "No customizations defined for $(IMAGE), skipping..."; \
		rm -rf $$TEMP_DIR; \
		exit 0; \
	fi; \
	\
	echo "# Customized DHI Image" > $$TEMP_DIR/Dockerfile; \
	echo "FROM $(DOCKER_REGISTRY)/$(IMAGE):$(GIT_TAG)-$(VARIANT)-$(OS)" >> $$TEMP_DIR/Dockerfile; \
	echo "" >> $$TEMP_DIR/Dockerfile; \
	\
	for ARTIFACT in $$ALL_CUSTOMIZATIONS; do \
		[ -z "$$ARTIFACT" ] && continue; \
		echo "Building OCI artifact: $$ARTIFACT"; \
		$(MAKE) build-artifact-$$ARTIFACT > /dev/null 2>&1 || { echo "Failed to build artifact $$ARTIFACT"; rm -rf $$TEMP_DIR; exit 1; }; \
		\
		GLOBAL_PATHS=$$(cat $(BUILD_CONFIG) | yq -r ".global_customizations[]? | select(.artifact == \"$$ARTIFACT\") | .paths[]? | \"\\(.src)|\\(.dest)\"" 2>/dev/null); \
		IMAGE_PATHS=$$(cat $(BUILD_CONFIG) | yq -r ".images[\"$(IMAGE)\"].customizations[]? | select(.artifact == \"$$ARTIFACT\") | .paths[]? | \"\\(.src)|\\(.dest)\"" 2>/dev/null); \
		\
		while IFS='|' read -r SRC DEST; do \
			[ -z "$$SRC" ] && continue; \
			echo "COPY --from=$(CUSTOMIZATION_REGISTRY)/dhi-customization-$$ARTIFACT:$(GIT_TAG) $$SRC $$DEST" >> $$TEMP_DIR/Dockerfile; \
		done <<< "$$(echo -e "$$GLOBAL_PATHS\n$$IMAGE_PATHS")"; \
	done; \
	\
	IMAGE_URL=$(DHI_REPO_URL)$(IMAGE)/$(OS)/$(VARIANT).yaml; \
	IMAGE_TAGS=$$(curl -s "$$IMAGE_URL" | yq -r '.tags[]' | sed 's|^|--tag $(DOCKER_REGISTRY)/$(IMAGE):|' | tr '\n' ' '); \
	docker buildx build \
		--platform $$IMAGE_PLATFORMS \
		--sbom=generator=dhi.io/scout-sbom-indexer:1 \
		--provenance=1 \
		$$TEMP_DIR \
		--file $$TEMP_DIR/Dockerfile \
		--tag $(DOCKER_REGISTRY)/$(IMAGE):$(GIT_TAG)-$(VARIANT)-$(OS) \
		$$IMAGE_TAGS \
		--load; \
	\
	rm -rf $$TEMP_DIR


# Customization targets
list-customizations:
	@echo "Available customization artifacts:"
	@echo "$(ARTIFACTS)" | tr ' ' '\n'

build-artifact-%: ARTIFACT=$*
build-artifact-%:
	$(call stage_status,build-artifact: $(ARTIFACT))
	@ARTIFACT_PLATFORMS=$$(cat $(CUSTOMIZATIONS_CONFIG) | yq -r '.artifacts["$(ARTIFACT)"].platforms[]?' 2>/dev/null | tr '\n' ',' | sed 's/,$$//' ); \
	ARTIFACT_PLATFORMS=$${ARTIFACT_PLATFORMS:-$(PLATFORMS)}; \
	docker buildx build \
		--platform $$ARTIFACT_PLATFORMS \
		--file $(shell cat $(CUSTOMIZATIONS_CONFIG) | yq -r '.artifacts["$(ARTIFACT)"].dockerfile') \
		--tag $(CUSTOMIZATION_REGISTRY)/dhi-customization-$(ARTIFACT):$(GIT_TAG) \
		customizations/$(ARTIFACT)

push-artifact-%: ARTIFACT=$*
push-artifact-%: build-artifact-$(ARTIFACT)
	$(call stage_status,push-artifact: $(ARTIFACT))
	@ARTIFACT_PLATFORMS=$$(cat $(CUSTOMIZATIONS_CONFIG) | yq -r '.artifacts["$(ARTIFACT)"].platforms[]?' 2>/dev/null | tr '\n' ',' | sed 's/,$$//' ); \
	ARTIFACT_PLATFORMS=$${ARTIFACT_PLATFORMS:-$(PLATFORMS)}; \
	docker buildx build \
		--platform $$ARTIFACT_PLATFORMS \
		--file $(shell cat $(CUSTOMIZATIONS_CONFIG) | yq -r '.artifacts["$(ARTIFACT)"].dockerfile') \
		--tag $(CUSTOMIZATION_REGISTRY)/dhi-customization-$(ARTIFACT):$(GIT_TAG) \
		--push \
		customizations/$(ARTIFACT)

build-customizations: $(addprefix build-artifact-,$(ARTIFACTS))
	$(call stage_status,build-customizations)

push-customizations: $(addprefix push-artifact-,$(ARTIFACTS))
	$(call stage_status,push-customizations)


# Build customized image combinations
$(addprefix build-customized-combination-,$(ALL_COMBINATIONS)): build-customized-combination-%:
	@IMAGE_NAME=$$(echo '$*' | cut -d, -f1); \
	IMAGE_OS=$$(echo '$*' | cut -d, -f2); \
	IMAGE_VARIANT=$$(echo '$*' | cut -d, -f3); \
	$(MAKE) build-customized-image IMAGE=$$IMAGE_NAME OS=$$IMAGE_OS VARIANT=$$IMAGE_VARIANT

build-customized: $(addprefix build-customized-combination-,$(ALL_COMBINATIONS))
	$(call stage_status,build-customized)
clean:
	@docker image rm -f $(shell docker image ls --format "{{.Repository}}:{{.Tag}}" --filter=dangling=false --filter=reference="$(DOCKER_REGISTRY)/*:*") 2>/dev/null || true

prune:
	@docker system prune --all --force --volumes
	@docker buildx prune --all --force

summary:
	$(call summary)
