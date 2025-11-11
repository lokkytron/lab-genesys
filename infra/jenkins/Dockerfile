FROM jenkins/jenkins:lts
USER root

# Instala kubectl y otras herramientas necesarias
RUN apt-get update && \
    apt-get install -y apt-transport-https ca-certificates curl gnupg
RUN curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
RUN echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
RUN apt-get update
RUN apt-get install -y kubectl docker.io

# Asegura que kubectl esté en el PATH
ENV PATH="/usr/bin:${PATH}"

# Cambia al usuario jenkins
USER jenkins
