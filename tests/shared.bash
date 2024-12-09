export HTTPD_PORT=${HTTPD_PORT:-1024}
[ "$BATS_LIB_PATH" = /usr/lib/bats ] && BATS_LIB_PATH=~/.bats/lib:$BATS_LIB_PATH

strict() { set -euo pipefail; shopt -s inherit_errexit; "$@"; }

ml() { for l; do printf '%s\n' "$l"; done; }

run_ncat_server() {
    local host=$1 port=$2
    ncat -lk -- "$host" "$port" &
    ncat_pid=$!
    wait4port "$host" "$port"
}

wait4port() {
    local host=$1 port=$2
    if command -v wait4ports >/dev/null; then
        wait4ports -t 5 tcp://"$host:$port"
    else
        wait-for-it -t 5 "$host:$port"
    fi
}
