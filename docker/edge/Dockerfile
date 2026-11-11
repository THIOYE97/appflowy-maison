# syntax=docker/dockerfile:1
# Public entrypoint for the Railway deployment: routes /api, /ws, /gotrue and
# /console to the backend services and everything else to the web SPA.
FROM nginx:alpine

# envsubst ships in gettext, not in the base image.
RUN apk add --no-cache gettext

COPY docker/edge/nginx.conf.template /etc/nginx/nginx.conf.template
COPY docker/edge/docker-entrypoint.sh /docker-entrypoint-edge.sh
RUN chmod +x /docker-entrypoint-edge.sh

ENTRYPOINT ["/docker-entrypoint-edge.sh"]
