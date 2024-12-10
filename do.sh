#!/usr/bin/env bash
set -eu
prj_root=`dirname -- "$0"`
. "$prj_root"/common.sh

[ -f ~/.getcert ] && config_file=~/.getcert || config_file=/etc/getcert

email=`getvar "$config_file" email`
if ! [ "$email" ]; then
    printf '%s: email is required\n' "$0" >&2
    exit 1
fi

docroot=`getvar "$config_file" docroot`

[ -d ~/.getcert.d ] && config_dir=~/.getcert.d || config_dir=/etc/getcert.d
if ! [ -d "$config_dir" ]; then
    exit
fi

web_server_running=`web_server_running && echo 1 || true`

if ! [ "$web_server_running" ]; then
    httpd_cid=`"$prj_root"/httpd.sh`
fi

declare -A seen_renew_hooks
pending_renew_hooks=()
exit_code=0
for f in "$config_dir"/*; do
    getarr "$f" domains
    if [ ${#domains[@]} -eq 0 ]; then
        printf '%s: at least one domain must be specified (%s)\n' "$0" "$f" >&2
        exit_code=1
        continue
    fi
    staging=`getvar "$f" staging`
    echo "Obtaining a certificate for ${domains[0]}..."
    r=0
    "$prj_root"/do1.sh --managed ${web_server_running:+--web-server-running} \
        ${docroot:+--docroot "$docroot"} \
        --email "$email" \
        ${staging:+--staging} \
        -- \
        "${domains[@]}" \
        || r=$?
    if [ "$r" = 0 ]; then
        getarr "$f" renew_hooks
        for h in ${renew_hooks[*]+"${renew_hooks[@]}"}; do
            if ! [[ -v seen_renew_hooks[$h] ]]; then
                seen_renew_hooks[$h]=1
                pending_renew_hooks+=("$h")
            fi
        done
    elif [ "$r" -gt 1 ]; then
        exit_code=1
    fi
done

if [ "${httpd_cid-}" ]; then
    quiet docker stop -- "$httpd_cid"
fi

for h in ${pending_renew_hooks[*]+"${pending_renew_hooks[@]}"}; do
    sh -c "$h" || if [ "$exit_code" = 0 ]; then exit_code=2; fi
done

exit $exit_code
