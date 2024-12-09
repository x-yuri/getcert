#!/usr/bin/env bash
set -euo pipefail
prj_root=`dirname -- "$0"`
. "$prj_root"/common.sh

if ! [ "`docker images -q getcert-httpd`" ]; then
    tmp=`mktemp`
    trap "rm ${tmp@Q}" EXIT
    cat >"$tmp" <<\EOF
FROM alpine:3.20
RUN apk add --no-cache busybox-extras
WORKDIR docroot
EOF
    quiet docker build -t getcert-httpd -f "$tmp" .
fi

docker run -d --init -v getcert:/docroot -p "${HTTPD_PORT:-80}":80 \
    getcert-httpd busybox-extras httpd -f
