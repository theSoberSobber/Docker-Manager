FROM node:20-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

COPY server.js ./

# Copy Firebase service account if present (glob trick avoids COPY failure when missing)
COPY firebase-service-account.jso[n] ./

EXPOSE 7847

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:7847/health || exit 1

CMD ["node", "server.js"]
