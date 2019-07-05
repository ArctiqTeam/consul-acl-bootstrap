FROM alpine:3.8

LABEL maintainer="tim.fairweather@arctiq.ca"

# Install Kubectl
ADD https://storage.googleapis.com/kubernetes-release/release/v1.14.1/bin/linux/amd64/kubectl /usr/local/bin/kubectl

# Install the bootstrap script
ADD bootstrap.sh /usr/local/bin/bootstrap

ENV HOME=/config

RUN set -x && \
    apk add --no-cache jq curl bash ca-certificates && \
    chmod +x /usr/local/bin/kubectl && \
    \
    # Create non-root user (with a randomly chosen UID/GUI).
    adduser kubectl -Du 2342 -h /config

USER kubectl

ENTRYPOINT ["/usr/local/bin/bootstrap"]
