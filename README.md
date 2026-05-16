# Docker Hardened Images (DHI) Customization

This repository provides an automated workflow to track, build, and customize [Docker Hardened Images](https://docs.docker.com/dhi/). It allows you to pull DHI base images and inject your own custom configurations (such as corporate proxies, certificates, or package manager preferences) to produce customized, hardened base images.

## Overview for Humans

The customization system relies on three main configuration files and a Makefile:

- **`images.yaml`**: Defines which DHI images you want to track (including supported platforms, OS versions, and tags). It also specifies which customizations to apply to all images (`global_customizations`) or to specific images.
- **`customizations.yaml`**: Defines OCI Artifacts. Each artifact represents a specific customization (e.g., a proxy config) and points to a directory containing a `FROM scratch` Dockerfile.
- **`CUSTOMIZATIONS.md`**: Detailed documentation explaining the structure of customizations and how to create new ones.
- **`Makefile`**: The core build engine. It orchestrates the entire workflow, from building the OCI artifacts to generating dynamic Dockerfiles that weave the customizations into the final base images.

### The Build Flow

1. **Define Targets**: Specify the images you want to replicate in `images.yaml`.
2. **Define Customizations**: Create an OCI artifact in `customizations.yaml` and reference it in `images.yaml` (mapping the `src` paths in the artifact to the `dest` paths in the final image).
3. **Artifact Compilation**: When triggered, the `Makefile` builds these artifacts (which contain only your custom files, nothing else).
4. **Dynamic Assembly**: The `Makefile` dynamically generates a temporary Dockerfile for each target image:
   ```dockerfile
   FROM <dhi-base-image>
   COPY --from=<customization-artifact> /src/path /dest/path
   ```
5. **Final Image**: The customized image is built via `docker buildx` and tagged appropriately.

### Common Commands

- `make build`: Builds all base images defined in `images.yaml`.
- `make build-customizations`: Builds the OCI artifacts defined in `customizations.yaml` without applying them.
- `make build-images`: Builds all base images defined in `images.yaml`.
- `make build-customized-images`: Builds all customized images by applying the artifacts on top of the base images.
- `make build-customized-image IMAGE=amazoncorretto OS=alpine-3.23 VARIANT=21`: Builds a specific customized image combination.

For more details on defining and applying new customizations, read `CUSTOMIZATIONS.md`.
