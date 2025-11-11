# Usa una imagen base de agente de Jenkins ligera
FROM jenkins/inbound-agent:alpine

# Cambia a root temporalmente para instalar herramientas
USER root

# Actualiza el índice de paquetes e instala las dependencias necesarias
# git: para clonar repositorios
# docker: para construir imágenes
# openjdk11: para que Jenkins pueda ejecutar el agente
# curl: útil para descargas
RUN apk update && apk add --no-cache git docker openjdk11-jdk-headless curl

# Vuelve a cambiar al usuario jenkins por seguridad
USER jenkins
