## 🤖 AI Agent Instructions

If you are an AI assistant working on this repository, please adhere to the following rules and architectural constraints:

### Repository Context
1. **Scope**: This repository is designed exclusively for building and extending **base images**, not full applications.
2. **OCI Artifact Pattern**: Customizations are injected using lightweight OCI artifacts. Artifact Dockerfiles (located in `customizations/<name>/Dockerfile`) **MUST** use `FROM scratch` and should generally only contain `COPY` instructions. Avoid adding OS package managers (`apk`, `apt`) or run scripts to the artifacts.

### Modifying Customizations
When tasked with adding a new customization (e.g., adding a corporate CA certificate or pip config):
1. **Create Files**: Create `customizations/<new-config>/Dockerfile` (FROM scratch) and the associated config files.
2. **Register Artifact**: Add the artifact definition to `customizations.yaml`.
3. **Apply Artifact**: Update `images.yaml`. Add the artifact to `global_customizations` if it applies universally, or to a specific image's `customizations` array. You must provide the `paths` mapping (`src` -> `dest`).
4. **Document**: If the new customization pattern is non-standard, update `CUSTOMIZATIONS.md`.

### Build System Guidelines
1. **Makefile Execution**: The `Makefile` heavily relies on `yq` to parse YAML files, `curl` to fetch upstream DHI manifests, and `docker buildx`. Ensure any shell commands you write in the Makefile are compatible with these tools.
2. **Dynamic Dockerfiles**: The `build-customized-image` target generates temporary Dockerfiles on the fly using echo statements to assemble the `FROM` and `COPY --from` commands. Modify this logic very carefully, as breaking it will break the entire customization pipeline.
3. **Synchronization**: Always ensure `images.yaml` and `customizations.yaml` schemas remain synchronized. If an artifact is referenced in `images.yaml` but missing from `customizations.yaml`, the build will fail.
