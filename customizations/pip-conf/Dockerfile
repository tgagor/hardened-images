# syntax=docker/dockerfile:1
# OCI Artifact: Custom pip configuration
# This minimal image contains a custom pip.conf file for pip proxy settings

FROM scratch

# Copy the custom pip.conf into the artifact
# When used in DHI customization, specify path: /etc/pip.conf
COPY pip.conf /etc/pip.conf
