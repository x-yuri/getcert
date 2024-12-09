web_server_running() {
    { echo -n > /dev/tcp/localhost/"${HTTPD_PORT:-80}"; } 2>/dev/null
}

docker_pull() {
    local image=$1
    if ! [ "`docker images -q -- "$image"`" ]; then
        quiet docker pull -- "$image"
    fi
}

getvar() {
    eval "$2"=
    . "$1"
    printf '%s\n' "${!2}"
}

getarr() {
    [ "$2" = a ] || local -n a=$2
    a=()
    while IFS= read -r; do
        a+=("$REPLY")
    done < <(
        . "$1"
        eval '
            for __el in ${'"$2"'[*]+"${'"$2"'[@]}"}; do
                printf "%s\n" "$__el"
            done
        '
    )
}

quiet() {
    local tmp
    tmp=`mktemp`
    "$@" >"$tmp" 2>&1 || {
        local r=$?
        cat -- "$tmp"
        rm -- "$tmp"
        exit $r
    }
    rm -- "$tmp"
}
