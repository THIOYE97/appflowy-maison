#!/bin/sh
# Renders the edge config, then hands over to nginx.
#
# The resolver address has to be discovered at runtime: Railway's internal DNS
# is not a documented fixed address, and a wrong one silently turns every
# proxy_pass into a 502. An IPv6 nameserver needs bracketing to be valid in an
# nginx `resolver` directive.
set -eu

: "${PORT:=80}"
: "${CLOUD_UPSTREAM:=appflowy-cloud.railway.internal:8000}"
: "${GOTRUE_UPSTREAM:=gotrue.railway.internal:9999}"
: "${ADMIN_UPSTREAM:=admin-frontend.railway.internal:3000}"
: "${WEB_UPSTREAM:=appflowy-web.railway.internal:80}"

RESOLVER="$(awk '/^nameserver/ { print $2; exit }' /etc/resolv.conf)"
if [ -z "$RESOLVER" ]; then
    echo "edge: no nameserver in /etc/resolv.conf, falling back to 127.0.0.11" >&2
    RESOLVER="127.0.0.11"
fi
# Bracket IPv6 literals; the colon test is safe because IPv4 never contains one.
case "$RESOLVER" in
    *:*) RESOLVER="[$RESOLVER]" ;;
esac

export PORT CLOUD_UPSTREAM GOTRUE_UPSTREAM ADMIN_UPSTREAM WEB_UPSTREAM RESOLVER

# Only the listed names are substituted — nginx's own $variables must survive.
envsubst '${RESOLVER} ${PORT} ${CLOUD_UPSTREAM} ${GOTRUE_UPSTREAM} ${ADMIN_UPSTREAM} ${WEB_UPSTREAM}' \
    < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

echo "edge: resolver=${RESOLVER} port=${PORT}"
nginx -t
exec nginx -g 'daemon off;'
