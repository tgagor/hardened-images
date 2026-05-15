# syntax=docker/dockerfile:1
# OCI Artifact: Custom .npmrc configuration
# This minimal image contains a custom .npmrc file for npm proxy settings

FROM scratch

# Copy the custom .npmrc into the artifact
# When used in DHI customization, specify path: /root/.npmrc
COPY .npmrc /root/.npmrc
