# Jarvis Live: tiny Node server, no npm packages
FROM node:22-alpine
WORKDIR /app
COPY server.mjs ./
COPY public ./public
USER node
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/health || exit 1
CMD ["node", "server.mjs"]
