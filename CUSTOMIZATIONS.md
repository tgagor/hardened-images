# DHI Customizations

This directory contains OCI artifact images for customizing Docker Hardened Images (DHI).

## Overview

You can apply customizations to DHI images in two ways:

1. **Local customizations** (Makefile-based) — Build customized images directly in your Makefile
2. **Docker Hub customizations** — Use Docker Hub UI to apply customizations (requires DHI Select/Enterprise)

This guide focuses on local customizations.

## Structure

```
customizations/
├── npmrc/                    # Example: Custom npm configuration
│   ├── Dockerfile           # OCI artifact definition (FROM scratch)
│   └── .npmrc              # The config file to include
└── ca-cert/                # Example: Custom CA certificate
    ├── Dockerfile
    └── ca-bundle.crt
```

## Local Customization Workflow

### 1. Define Customizations

Edit your `images.yaml` to specify:
- **Global customizations** — applied to all images
- **Per-image customizations** — applied only to specific images

```yaml
global_customizations:
  # - artifact: ca-cert
  #   paths:
  #     - src: /etc/ssl/certs/ca-certificates.crt
  #       dest: /etc/ssl/certs/ca-certificates.crt

images:
  amazoncorretto:
    customizations:
      - artifact: npmrc
        paths:
          - src: /root/.npmrc
            dest: /root/.npmrc
```

Each path mapping specifies:
- `artifact` — the OCI artifact name (must exist in `customizations.yaml`)
- `src` — source path inside the OCI artifact
- `dest` — destination path in the final image

### 2. Create OCI Artifacts

Add artifacts to `customizations.yaml`:

```yaml
artifacts:
  npmrc:
    description: "Custom .npmrc configuration"
    dockerfile: "customizations/npmrc/Dockerfile"
    push: true
    platforms:
      - linux/amd64
      - linux/arm64
```

Create the Dockerfile as a minimal OCI artifact:

```dockerfile
# syntax=docker/dockerfile:1
FROM scratch
COPY .npmrc /root/.npmrc
```

### 3. Build Customized Images

```bash
# Build all customized images with their artifacts
make build-customized

# Build specific customized image
make build-customized-image IMAGE=amazoncorretto OS=alpine-3.23 VARIANT=21

# Build just the OCI artifacts (without applying them)
make build-customizations

# Push OCI artifacts to registry
make push-customizations
```

### 4. Verify Results

```bash
docker images | grep dhi
# Shows images tagged with `_custom` suffix by default
```

## How It Works

When you run `make build-customized-image`:

1. **Collects customizations** — Reads from `images.yaml` which OCI artifacts apply
2. **Builds OCI artifacts** — Ensures all required customizations are built locally
3. **Generates Dockerfile** — Creates a dynamic Dockerfile that:
   ```dockerfile
   FROM <base-dhi-image-url>
   COPY --from=<oci-artifact> <src> <dest>
   ```
4. **Builds customized image** — Runs docker buildx with the generated Dockerfile
5. **Tags with suffix** — Tags as `image-name_custom:tag` (customizable via `CUSTOMIZATION_SUFFIX`)

## Available Commands

### Building
- `make build` — Build all base images
- `make build-customized` — Build all images with customizations applied
- `make build-artifact-npmrc` — Build specific OCI artifact
- `make build-customized-image IMAGE=amazoncorretto OS=alpine-3.23 VARIANT=21` — Build specific customized image

### OCI Artifacts
- `make list-customizations` — List all configured artifacts
- `make build-customizations` — Build all OCI artifacts locally
- `make push-customizations` — Build and push all OCI artifacts

### Customization
- `make build-customized` — Build all images with customizations
- `make build-customized-image IMAGE=<name> OS=<os> VARIANT=<variant>` — Build one customized image

## Creating New Customizations

### 1. Create directory and files

```bash
mkdir -p customizations/my-custom-config
touch customizations/my-custom-config/Dockerfile
touch customizations/my-custom-config/my-config-file
```

### 2. Create the Dockerfile

```dockerfile
# syntax=docker/dockerfile:1
FROM scratch

COPY my-config-file /etc/my-app/config
COPY other-file /etc/my-app/other
```

### 3. Add to `customizations.yaml`

```yaml
artifacts:
  my-custom-config:
    description: "My custom configuration"
    dockerfile: "customizations/my-custom-config/Dockerfile"
    push: true
    platforms:
      - linux/amd64
      - linux/arm64
```

### 4. Reference in `images.yaml`

**Global (apply to all images):**
```yaml
global_customizations:
  - artifact: my-custom-config
    paths:
      - src: /etc/my-app/config
        dest: /etc/my-app/config
```

**Per-image (apply only to specific images):**
```yaml
images:
  amazoncorretto:
    customizations:
      - artifact: my-custom-config
        paths:
          - src: /etc/my-app/config
            dest: /etc/my-app/config
```

### 5. Build and verify

```bash
make build-customized-image IMAGE=amazoncorretto OS=alpine-3.23 VARIANT=21
```

## Configuration Variables

- `CUSTOMIZATION_SUFFIX` — Suffix added to customized image tags (default: `_custom`)
- `CUSTOMIZATION_REGISTRY` — Registry for OCI artifacts (default: `$(DOCKER_REGISTRY)`)
- `PLATFORMS` — Default platforms if not specified per-image/artifact

## Example: Adding .npmrc

The included `npmrc` customization is already set up for Node.js images:

1. **Edit** `customizations/npmrc/.npmrc` with your proxy/registry:
   ```ini
   registry=https://your-private-registry.com/
   http-proxy=http://proxy.example.com:8080
   //your-registry.com/:_authToken=YOUR_TOKEN
   ```

2. **Add to image** in `images.yaml`:
   ```yaml
   amazoncorretto:
     customizations:
       - artifact: npmrc
         paths:
           - src: /root/.npmrc
             dest: /root/.npmrc
   ```

3. **Build**:
   ```bash
   make build-customized-image IMAGE=amazoncorretto OS=alpine-3.23 VARIANT=21
   ```

## Best Practices

- **Use multi-stage builds** in OCI artifact Dockerfiles to keep images minimal
- **Include only necessary files** in OCI artifacts
- **Test customizations locally** before pushing
- **Tag artifacts with versions** in `customizations.yaml` for reproducibility
- **Document file ownership** — images start as `root` or `nobody` by default
- **Verify file permissions** in the final image match expectations
