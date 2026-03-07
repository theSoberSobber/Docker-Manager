FROM docker:24-cli AS base

# Use Alpine for minimal footprint
RUN apk add --no-cache curl jq

WORKDIR /app

COPY notifier.sh /app/notifier.sh
COPY healthcheck.sh /app/healthcheck.sh
COPY scripts/ /app/scripts/

# Fix Windows CRLF -> Unix LF line endings
RUN sed -i 's/\r$//' /app/notifier.sh /app/healthcheck.sh /app/scripts/*.sh && \
    chmod +x /app/notifier.sh /app/healthcheck.sh /app/scripts/*.sh

# Environment variables (set by the app during deployment)
ENV PAIRING_TOKEN=""
ENV BACKEND_URL=""
ENV SERVER_ID=""
ENV EVENT_TYPES="container"
ENV NOTIFIER_VERSION="1.0.0"

# Health check — verifies the process is alive and backend is reachable
HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=10s \
  CMD /app/healthcheck.sh

# Labels for identification
LABEL org.opencontainers.image.title="Docker Manager Notifier"
LABEL org.opencontainers.image.description="Watches Docker events and forwards them to Docker Manager Pro backend"
LABEL org.opencontainers.image.source="https://github.com/theSoberSobber/Docker-Manager"

ENTRYPOINT ["/app/notifier.sh"]
