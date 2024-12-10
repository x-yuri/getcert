setup() {
    load shared
    bats_load_library bats-support
    bats_load_library bats-assert
    bats_load_library bats-file
    bats_load_library bats-mock/stub.bash
    strict
    mkdir -- "$BATS_TEST_TMPDIR"/home
}

mkconf() {
    local base=.getcert docroot= domains=() renew_hooks=() staging=()
    while [ $# -gt 0 ]; do
        case "$1" in
        --system) base=getcert
                  shift;;
        --docroot) docroot=$2
                   shift 2;;
        -d) domains+=("$2")
            renew_hooks+=('')
            staging+=('')
            shift 2;;
        --renew-hook) if [ "${renew_hooks[-1]}" ]; then
                          renew_hooks[-1]+=\|$2
                      else
                          renew_hooks[-1]=$2
                      fi
                      shift 2;;
        --staging) staging[-1]=1
                   shift;;
        esac
    done

    {
        echo email=someone@gmail.com
        if [ "$docroot" ]; then
            echo docroot="$docroot"
        fi
    } > "$BATS_TEST_TMPDIR"/home/"$base"

    if [ ${#domains[*]} -eq 0 ]; then return; fi

    mkdir -- "$BATS_TEST_TMPDIR"/home/"$base".d

    local i=0
    for d in "${domains[@]}"; do
        local first_domain=${d%% *}
        {
            echo "domains=($d)"
            if [ "${renew_hooks[i]}" ]; then
                local els
                IFS=\| read -ra els <<< "${renew_hooks[i]}"
                local j
                for (( j = 0; j < ${#els[*]}; j++ )); do
                    els[j]=${els[j]@Q}
                done
                echo "renew_hooks=(${els[*]+${els[*]}})"
            fi
            if [ "${staging[i]}" ]; then
                echo staging=1
            fi
        } > "$BATS_TEST_TMPDIR"/home/"$base".d/"${first_domain:-dummy}"
        i=$(( i + 1 ))
    done
}

docker_images_httpd_cmd() {
    echo images -q getcert-httpd \
        : echo getcert-httpd
}

docker_run_httpd_cmd() {
    echo run -d --init \
        -v getcert:/docroot \
        -p $HTTPD_PORT:80 \
        getcert-httpd busybox-extras httpd -f \
        : echo cid
}

docker_stop_httpd_cmd() {
    echo stop -- cid : echo cid
}

docker_images_simp_le_cmd() {
    echo images -q -- zenhack/simp_le : echo zenhack/simp_le
}

docker_run_simp_le_cmd() {
    local domains=() first_domain volumes=() server=() exit_code=0
    while [ $# -gt 0 ]; do
        case "$1" in
        -d) domains+=("$1" "$2")
            if ! [ "${first_domain-}" ]; then
                first_domain=$2
            fi
            shift 2;;
        -v) volumes+=("$1" "$2")
            shift 2;;
        --server) server=("$1" "$2")
                  shift 2;;
        --exit-code) exit_code=$2
                     shift 2;;
        esac
    done
    if [ ${#volumes[*]} -eq 0 ]; then
        volumes=(-v getcert:/docroot)
    fi
    if [ ${#server[*]} -eq 0 ]; then
        server=(--server https://acme-v02.api.letsencrypt.org/directory)
    fi

    echo run --rm \
        ${volumes[@]} \
        -v /etc/certs/$first_domain:/simp_le/certs \
        zenhack/simp_le \
        --email someone@gmail.com \
        --default_root /docroot \
        ${server[@]} \
        -f key.pem \
        -f cert.pem \
        -f account_key.json \
        -f account_reg.json \
        -f chain.pem \
        -f fullchain.pem \
        -- \
        ${domains[@]} \
        : exit $exit_code
}

@test 'email is required' {
    run ./do.sh

    assert_equal "$status" 1
    assert_output --partial 'email is required'
}

@test 'does nothing if no certs are configured' {
    mkconf

    HOME=$BATS_TEST_TMPDIR/home \
        ./do.sh
}

@test 'at least one domain must be specified' {
    mkconf -d ''
    stub docker "`docker_images_httpd_cmd`" \
                "`docker_run_httpd_cmd`" \
                "`docker_stop_httpd_cmd`"

    HOME=$BATS_TEST_TMPDIR/home \
        run ./do.sh

    assert_equal "$status" 1
    assert_output --partial 'at least one domain must be specified'
}

@test 'no domains case must not affect other certificates' {
    mkconf -d '' \
           -d example.com
    stub docker "`docker_images_httpd_cmd`" \
                "`docker_run_httpd_cmd`" \
                "`docker_images_simp_le_cmd`" \
                "`docker_run_simp_le_cmd \
                    -d example.com`" \
                "`docker_stop_httpd_cmd`"

    HOME=$BATS_TEST_TMPDIR/home \
        run ./do.sh

    assert_equal "$status" 1
    assert_output --partial 'Obtaining a certificate for example.com'
}

@test 'obtains a certificate' {
    mkconf -d example.com
    stub docker "`docker_images_httpd_cmd`" \
                "`docker_run_httpd_cmd`" \
                "`docker_images_simp_le_cmd`" \
                "`docker_run_simp_le_cmd \
                    -d example.com`" \
                "`docker_stop_httpd_cmd`"

    HOME=$BATS_TEST_TMPDIR/home \
        ./do.sh
}

@test 'obtains a certificate using configs in /etc' {
    mkconf --system -d example.com
    stub docker "`docker_images_httpd_cmd`" \
                "`docker_run_httpd_cmd`" \
                "`docker_images_simp_le_cmd`" \
                "`docker_run_simp_le_cmd \
                    -d example.com`" \
                "`docker_stop_httpd_cmd`"

    with_changed_etc \
        ./do.sh
}

@test 'obtains a certificate with a running web server' {
    mkconf --docroot "$BATS_TEST_TMPDIR"/docroot \
           -d example.com
    run_ncat_server localhost "$HTTPD_PORT"
    stub docker "`docker_images_simp_le_cmd`" \
                "`docker_run_simp_le_cmd \
                    -d example.com \
                    -v "$BATS_TEST_TMPDIR"/docroot:/docroot`"

    HOME=$BATS_TEST_TMPDIR/home \
        ./do.sh
}

@test 'obtains 2 certificates' {
    mkconf -d example1.com -d example2.com
    stub docker "`docker_images_httpd_cmd`" \
                "`docker_run_httpd_cmd`" \
                "`docker_images_simp_le_cmd`" \
                "`docker_run_simp_le_cmd \
                    -d example1.com`" \
                "`docker_images_simp_le_cmd`" \
                "`docker_run_simp_le_cmd \
                    -d example2.com`" \
                "`docker_stop_httpd_cmd`"

    HOME=$BATS_TEST_TMPDIR/home \
        ./do.sh
}

@test 'obtains a certificate for 2 domains' {
    mkconf -d 'example1.com example2.com'
    stub docker "`docker_images_httpd_cmd`" \
                "`docker_run_httpd_cmd`" \
                "`docker_images_simp_le_cmd`" \
                "`docker_run_simp_le_cmd \
                    -d example1.com -d example2.com`" \
                "`docker_stop_httpd_cmd`"

    HOME=$BATS_TEST_TMPDIR/home \
        ./do.sh
}

@test 'runs a hook' {
    mkconf -d example.com \
           --renew-hook "touch ${BATS_TEST_TMPDIR@Q}/renew-hook"
    stub docker "`docker_images_httpd_cmd`" \
                "`docker_run_httpd_cmd`" \
                "`docker_images_simp_le_cmd`" \
                "`docker_run_simp_le_cmd \
                    -d example.com`" \
                "`docker_stop_httpd_cmd`"

    HOME=$BATS_TEST_TMPDIR/home \
        ./do.sh

    assert_file_exists "$BATS_TEST_TMPDIR"/renew-hook
}

@test 'runs 2 hooks' {
    mkconf -d example.com \
           --renew-hook "touch ${BATS_TEST_TMPDIR@Q}/renew-hook1" \
           --renew-hook "touch ${BATS_TEST_TMPDIR@Q}/renew-hook2"
    stub docker "`docker_images_httpd_cmd`" \
                "`docker_run_httpd_cmd`" \
                "`docker_images_simp_le_cmd`" \
                "`docker_run_simp_le_cmd \
                    -d example.com`" \
                "`docker_stop_httpd_cmd`"

    HOME=$BATS_TEST_TMPDIR/home \
        ./do.sh

    assert_file_exists "$BATS_TEST_TMPDIR"/renew-hook1
    assert_file_exists "$BATS_TEST_TMPDIR"/renew-hook2
}

@test "doesn't run a hook twice" {
    mkconf -d example1.com \
           --renew-hook "echo -n 1 >> ${BATS_TEST_TMPDIR@Q}/renew-hook" \
           -d example2.com \
           --renew-hook "echo -n 1 >> ${BATS_TEST_TMPDIR@Q}/renew-hook"
    stub docker "`docker_images_httpd_cmd`" \
                "`docker_run_httpd_cmd`" \
                "`docker_images_simp_le_cmd`" \
                "`docker_run_simp_le_cmd \
                    -d example1.com`" \
                "`docker_images_simp_le_cmd`" \
                "`docker_run_simp_le_cmd \
                    -d example2.com`" \
                "`docker_stop_httpd_cmd`"

    HOME=$BATS_TEST_TMPDIR/home \
        ./do.sh

    assert_file_contains "$BATS_TEST_TMPDIR"/renew-hook ^1$
}

@test "failure of one hook doesn't prevent the other hook from running" {
    mkconf -d example.com \
           --renew-hook 'exit 1' \
           --renew-hook "touch ${BATS_TEST_TMPDIR@Q}/renew-hook"
    stub docker "`docker_images_httpd_cmd`" \
                "`docker_run_httpd_cmd`" \
                "`docker_images_simp_le_cmd`" \
                "`docker_run_simp_le_cmd \
                    -d example.com`" \
                "`docker_stop_httpd_cmd`"

    HOME=$BATS_TEST_TMPDIR/home \
        run ./do.sh

    assert_file_exists "$BATS_TEST_TMPDIR"/renew-hook
}

@test "doesn't run hooks if the certificate already exists" {
    mkconf -d example.com \
           --renew-hook "touch ${BATS_TEST_TMPDIR@Q}/renew-hook"
    stub docker "`docker_images_httpd_cmd`" \
                "`docker_run_httpd_cmd`" \
                "`docker_images_simp_le_cmd`" \
                "`docker_run_simp_le_cmd \
                    -d example.com \
                    --exit-code 1`" \
                "`docker_stop_httpd_cmd`"

    HOME=$BATS_TEST_TMPDIR/home \
        ./do.sh

    assert_file_not_exists "$BATS_TEST_TMPDIR"/renew-hook
}

@test "doesn't run hooks if there was an error while obtaining the certificate" {
    mkconf -d example.com \
           --renew-hook "touch ${BATS_TEST_TMPDIR@Q}/renew-hook"
    stub docker "`docker_images_httpd_cmd`" \
                "`docker_run_httpd_cmd`" \
                "`docker_images_simp_le_cmd`" \
                "`docker_run_simp_le_cmd \
                    -d example.com \
                    --exit-code 2`" \
                "`docker_stop_httpd_cmd`"

    HOME=$BATS_TEST_TMPDIR/home \
        run ./do.sh

    assert_file_not_exists "$BATS_TEST_TMPDIR"/renew-hook
}

@test 'obtains a staging certificate' {
    mkconf -d example.com --staging
    stub docker "`docker_images_httpd_cmd`" \
                "`docker_run_httpd_cmd`" \
                "`docker_images_simp_le_cmd`" \
                "`docker_run_simp_le_cmd \
                    -d example.com \
                    --server https://acme-staging-v02.api.letsencrypt.org/directory`" \
                "`docker_stop_httpd_cmd`"

    HOME=$BATS_TEST_TMPDIR/home \
        ./do.sh
}

@test 'exits with 0 if a certificate already exists' {
    mkconf -d example.com
    stub docker "`docker_images_httpd_cmd`" \
                "`docker_run_httpd_cmd`" \
                "`docker_images_simp_le_cmd`" \
                "`docker_run_simp_le_cmd \
                    -d example.com \
                    --exit-code 1`" \
                "`docker_stop_httpd_cmd`"

    HOME=$BATS_TEST_TMPDIR/home \
        ./do.sh
}

@test 'exits with 1 if there was an error while obtaining a certificate' {
    mkconf -d example.com
    stub docker "`docker_images_httpd_cmd`" \
                "`docker_run_httpd_cmd`" \
                "`docker_images_simp_le_cmd`" \
                "`docker_run_simp_le_cmd \
                    -d example.com \
                    --exit-code 2`" \
                "`docker_stop_httpd_cmd`"

    HOME=$BATS_TEST_TMPDIR/home \
        run ./do.sh

    assert_equal "$status" 1
}

@test 'exits with 2 if a hook failed' {
    mkconf -d example.com \
           --renew-hook 'exit 1'
    stub docker "`docker_images_httpd_cmd`" \
                "`docker_run_httpd_cmd`" \
                "`docker_images_simp_le_cmd`" \
                "`docker_run_simp_le_cmd \
                    -d example.com`" \
                "`docker_stop_httpd_cmd`"

    HOME=$BATS_TEST_TMPDIR/home \
        run ./do.sh

    assert_equal "$status" 2
}

teardown() {
    unstub docker
    if [ "${ncat_pid-}" ]; then
        kill -- "$ncat_pid" 2>/dev/null || true
    fi
    unchange_etc
}

with_changed_etc() {
    if [ "${ALLOW_CHANGING_ETC:-}" ]; then
        [ "$UID" = 1 ] && local sudo=() || local sudo=(sudo)
        "${sudo[@]}" cp -r -- "$BATS_TEST_TMPDIR"/home/* /etc
        etc_changed=1
        "$@"
    else
        touch -- "$BATS_TEST_TMPDIR"/home/bash.bashrc-override
        bwrap --dev-bind / / \
              --bind "$BATS_TEST_TMPDIR"/home /etc \
              "$@"
    fi
}

unchange_etc() {
    if [ "${ALLOW_CHANGING_ETC:-}" ] && [ "${etc_changed-}" ]; then
        [ "$UID" = 1 ] && local sudo=() || local sudo=(sudo)
        "${sudo[@]}" rm -r /etc/getcert /etc/getcert.d
    fi
}
