FROM node:20-alpine AS build
RUN apk add --no-cache git
RUN git clone --depth 1 https://github.com/AmazingAng/auth2api /src
WORKDIR /src
RUN npm ci && npm run build

FROM node:20-alpine
RUN apk add --no-cache gettext curl
WORKDIR /app
COPY --from=build /src/dist ./dist
COPY --from=build /src/node_modules ./node_modules
COPY --from=build /src/package.json .
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
VOLUME ["/data"]
EXPOSE 8317
ENTRYPOINT ["/entrypoint.sh"]
