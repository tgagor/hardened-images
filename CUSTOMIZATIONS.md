# DHI Customizations

This directory contains OCI artifact images for customizing Docker Hardened Images (DHI).

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

## How It Works

1. **OCI Artifacts** are minimal Docker images built with `FROM scratch` that contain only the files you want to add to DHI images
2. **Build** the artifacts: `make build-customizations` or `make build-artifact-npmrc`
3. **Push** to your registry: `make push-customizations` or `make push-artifact-npmrc`
4. **Use in Docker Hub** UI or CLI to reference the artifact when creating customizations

## Creating a New Customization

### 1. Create the directory and files

```bash
mkdir -p customizations/my-custom-config
touch customizations/my-custom-config/Dockerfile
touch customizations/my-custom-config/my-config-file
```

### 2. Create the Dockerfile

Follow the pattern for minimal OCI artifacts:

```dockerfile
# syntax=docker/dockerfile:1
FROM scratch

# Copy your configuration files
COPY my-config-file /etc/my-app/config
```

### 3. Add to customizations.yaml

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

### 4. Build and push

```bash
make build-artifact-my-custom-config
make push-artifact-my-custom-config

# Or all at once:
make push-customizations
```

## Using Customizations in Docker Hub

Once pushed, your OCI artifacts appear in the DHI customization workflow:

1. Go to Docker Hub > Hardened Images > Manage > Mirrored Images
2. Select an image to customize
3. In "OCI artifacts" section:
   - Repository: `tgagor/dhi`
   - Tag: `latest` (or your `GIT_TAG`)
   - Paths: Specify which files to include (e.g., `/root/.npmrc`)
4. Complete the customization

## Available Commands

- `make list-customizations` — List all configured artifacts
- `make build-customizations` — Build all artifacts locally
- `make push-customizations` — Build and push all artifacts
- `make build-artifact-npmrc` — Build specific artifact
- `make push-artifact-npmrc` — Push specific artifact

## Example: .npmrc Customization

The included `npmrc` artifact provides a custom npm configuration:

1. **Edit** `customizations/npmrc/.npmrc` with your proxy/registry settings
2. **Push** it: `make push-artifact-npmrc`
3. **Use in customization**: Select the `dhi-customization-npmrc:latest` artifact, include path `/root/.npmrc`
