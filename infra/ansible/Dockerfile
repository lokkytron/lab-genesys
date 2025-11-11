FROM cytopia/ansible:latest

# Install prerequisites
RUN apk add --no-cache \
      curl \
      jq \
      gnupg \
      openssh-client

# Add Smallstep package repository and key, then install step-cli
RUN echo "https://packages.smallstep.com/alpine/v3.16/main" >> /etc/apk/repositories && \
    curl -fsSL https://smallstep.com/keys/alpine-package-signing.pub \
      | tee /etc/apk/keys/alpine-package-signing.pub >/dev/null && \
    apk add --no-cache step-cli

# Add kubernetes.core.k8s modules
RUN pip install --no-cache-dir kubernetes openshift pyyaml jmespath
RUN ansible-galaxy collection install kubernetes.core

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
