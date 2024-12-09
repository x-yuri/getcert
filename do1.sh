#!/usr/bin/env bash
set -euo pipefail
shopt -s inherit_errexit
prj_root=`dirname -- "$0"`
. "$prj_root"/common.sh

usage() {
    cat >&2 <<EOF
Usage: $0 [OPTIONS...] DOMAINS...
  -d, --docroot=DOCROOT
  -e, --email=EMAIL
      --renew-hook
  -s, --staging          use the staging server
  -h, --help             display this help and exit
EOF
}

p_managed=
p_web_server_running=
p_docroot=
p_email=
p_renew_hooks=()
p_staging=
while getopts :d:e:sh-: option; do
    case "$option" in
    -)
        case "$OPTARG" in
        managed) p_managed=1;;
        web-server-running) p_web_server_running=1;;
        docroot)
            if [ $OPTIND -gt $# ]; then
                printf '%s: option --%s requires an argument\n' "$0" "$OPTARG" >&2
                usage
                exit 2
            fi
            p_docroot=${!OPTIND}
            OPTIND=$(( OPTIND + 1 ));;
        docroot=*)
            p_docroot=${OPTARG#*=};;
        email)
            if [ $OPTIND -gt $# ]; then
                printf '%s: option --%s requires an argument\n' "$0" "$OPTARG" >&2
                usage
                exit 2
            fi
            p_email=${!OPTIND}
            OPTIND=$(( OPTIND + 1 ));;
        email=*)
            p_email=${OPTARG#*=};;
        renew-hook)
            if [ $OPTIND -gt $# ]; then
                printf '%s: option --%s requires an argument\n' "$0" "$OPTARG" >&2
                usage
                exit 2
            fi
            p_renew_hooks+=("${!OPTIND}")
            OPTIND=$(( OPTIND + 1 ));;
        renew-hook=*)
            p_renew_hooks+=("${OPTARG#*=}");;
        staging) p_staging=1;;
        help)
            usage
            exit;;
        *)  printf '%s: unknown option (--%s)\n' "$0" "$OPTARG" >&2
            usage
            exit 2;;
        esac;;
    d)  p_docroot=$OPTARG;;
    e)  p_email=$OPTARG;;
    s)  p_staging=1;;
    h)  usage
        exit;;
    \?) printf '%s: unknown option (-%s)\n' "$0" "$OPTARG" >&2
        usage
        exit 2;;
    :)  printf '%s: option -%s requires an argument\n' "$0" "$OPTARG" >&2
        usage
        exit 2;;
    esac
done
shift $(( OPTIND - 1 ))

if ! [ "$p_email" ]; then
    printf '%s: email must be passed\n' "$0" >&2
    exit 2
fi
if [ ${#*} -eq 0 ]; then
    printf '%s: at least one domain must be passed\n' "$0" >&2
    exit 2
fi

p_first_domain=$1

[ "$p_managed" ] \
    && web_server_running=$p_web_server_running \
    || web_server_running=`web_server_running && echo 1 || true`

if ! [ "$p_managed" ] && ! [ "$web_server_running" ]; then
    httpd_cid=`"$prj_root"/httpd.sh`
fi

if [ "$web_server_running" ]; then
    if ! [ "$p_docroot" ]; then
        printf '%s: docroot was not specified\n' "$0" >&2
        exit 2
    fi
    docker_args=(-v "$p_docroot":/docroot)
else
    docker_args=(-v getcert:/docroot)
fi

for d; do
    ds+=(-d "$d")
done

[ "$p_staging" ] \
    && server=https://acme-staging-v02.api.letsencrypt.org/directory \
    || server=https://acme-v02.api.letsencrypt.org/directory

docker_pull zenhack/simp_le
r=0
docker run --rm \
    "${docker_args[@]}" \
    -v /etc/certs/"$p_first_domain":/simp_le/certs \
    zenhack/simp_le \
    --email "$p_email" \
    --default_root /docroot \
    --server "$server" \
    -f key.pem \
    -f cert.pem \
    -f account_key.json \
    -f account_reg.json \
    -f chain.pem \
    -f fullchain.pem \
    -- \
    "${ds[@]}" \
    || r=$?

if [ "${httpd_cid-}" ]; then
    quiet docker stop -- "$httpd_cid"
fi

if [ "$r" = 0 ]; then
    for h in ${p_renew_hooks[*]+"${p_renew_hooks[@]}"}; do
        sh -c "$h" || exit 2
    done
fi

exit $r
