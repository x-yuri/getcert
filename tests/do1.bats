setup() {
    load shared
    bats_load_library bats-support
    bats_load_library bats-assert
    bats_load_library bats-file
    bats_load_library bats-mock/stub.bash
    strict
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
    echo images -q -- zenhack/simp_le \
        : echo zenhack/simp_le
}

docker_run_simp_le_cmd() {
    local domains=() first_domain volumes=() email=() server=() exit_code=0
    while [ $# -gt 0 ]; do
        case "$1" in
        -d) domains+=("$1" "$2")
            if ! [ "${first_domain-}" ]; then
                first_domain=$2
            fi
            shift 2;;
        -v) volumes+=("$1" "$2")
            shift 2;;
        --email) email=("$1" "$2")
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
        ${email[@]} \
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

@test 'exits with 2 if no --docroot argument is passed' {
    run ./do1.sh --docroot

    assert_equal "$status" 2
    assert_output --partial 'option --docroot requires an argument'
}

@test 'exits with 2 if no -d argument is passed' {
    run ./do1.sh -d

    assert_equal "$status" 2
    assert_output --partial 'option -d requires an argument'
}

@test 'exits with 2 if no --email argument is passed' {
    run ./do1.sh --email

    assert_equal "$status" 2
    assert_output --partial 'option --email requires an argument'
}

@test 'exits with 2 if no -e argument is passed' {
    run ./do1.sh -e

    assert_equal "$status" 2
    assert_output --partial 'option -e requires an argument'
}

@test 'exits with 2 if no --renew-hook argument is passed' {
    run ./do1.sh --renew-hook

    assert_equal "$status" 2
    assert_output --partial 'option --renew-hook requires an argument'
}

@test 'exits with 2 if an unknown short option is passed' {
    run ./do1.sh -x

    assert_equal "$status" 2
    assert_output --partial 'unknown option (-x)'
}

@test 'exits with 2 if an unknown long option is passed' {
    run ./do1.sh --unknown-option

    assert_equal "$status" 2
    assert_output --partial 'unknown option (--unknown-option)'
}

@test 'exits with 2 if email is not passed' {
    run ./do1.sh

    assert_equal "$status" 2
    assert_output --partial 'email must be passed'
}

@test 'exits with 2 if no domains are passed' {
    run ./do1.sh --email someone@gmail.com

    assert_equal "$status" 2
    assert_output --partial 'at least one domain must be passed'
}

@test 'starts simp_le' {
    stub docker \
        "`docker_images_simp_le_cmd`" \
        "`docker_run_simp_le_cmd \
            --email someone@gmail.com \
            -d example.com`"

    ./do1.sh --email someone@gmail.com \
             --managed \
             example.com
}

@test 'starts a web server if --managed is not passed and no web server is running' {
    stub docker \
        "`docker_images_httpd_cmd`" \
        "`docker_run_httpd_cmd`" \
        "`docker_images_simp_le_cmd`" \
        "`docker_run_simp_le_cmd \
            --email someone@gmail.com \
            -d example.com`" \
        "`docker_stop_httpd_cmd`"

    ./do1.sh --email someone@gmail.com \
             example.com
}

@test "doesn't start a web server if --managed is not passed and a web server is running" {
    run_ncat_server localhost "$HTTPD_PORT"
    stub docker \
        "`docker_images_simp_le_cmd`" \
        "`docker_run_simp_le_cmd \
            --email someone@gmail.com \
            -d example.com \
            -v "$BATS_TEST_TMPDIR"/docroot:/docroot`"

    ./do1.sh --email someone@gmail.com \
             --docroot "$BATS_TEST_TMPDIR"/docroot \
             example.com
}

@test '--web-server-running requires --docroot' {
    run ./do1.sh --email someone@gmail.com \
                 --managed --web-server-running \
                 example.com

    assert_equal "$status" 2
    assert_output --partial 'docroot was not specified'
}

@test 'bind-mounts PATH into the simp_le container if --docroot PATH is passed' {
    stub docker \
        "`docker_images_simp_le_cmd`" \
        "`docker_run_simp_le_cmd \
            --email someone@gmail.com \
            -d example.com \
            -v "$BATS_TEST_TMPDIR"/docroot:/docroot`"

    ./do1.sh --email someone@gmail.com \
             --managed --web-server-running \
             --docroot "$BATS_TEST_TMPDIR"/docroot \
             example.com
}

@test 'bind-mounts PATH into the simp_le container if --docroot=PATH is passed' {
    stub docker \
        "`docker_images_simp_le_cmd`" \
        "`docker_run_simp_le_cmd \
            --email someone@gmail.com \
            -d example.com \
            -v "$BATS_TEST_TMPDIR"/docroot:/docroot`"

    ./do1.sh --email someone@gmail.com \
             --managed --web-server-running \
             --docroot="$BATS_TEST_TMPDIR"/docroot \
             example.com
}

@test 'bind-mounts PATH into the simp_le container if -d PATH is passed' {
    stub docker \
        "`docker_images_simp_le_cmd`" \
        "`docker_run_simp_le_cmd \
            --email someone@gmail.com \
            -d example.com \
            -v "$BATS_TEST_TMPDIR"/docroot:/docroot`"

    ./do1.sh --email someone@gmail.com \
             --managed --web-server-running \
             -d "$BATS_TEST_TMPDIR"/docroot \
             example.com
}

@test 'passes the email to simp_le if --email EMAIL is passed' {
    stub docker \
        "`docker_images_simp_le_cmd`" \
        "`docker_run_simp_le_cmd \
            --email someone@gmail.com \
            -d example.com`"

    ./do1.sh --email someone@gmail.com \
             --managed \
             example.com
}

@test 'passes the email to simp_le if --email=EMAIL is passed' {
    stub docker \
        "`docker_images_simp_le_cmd`" \
        "`docker_run_simp_le_cmd \
            --email someone@gmail.com \
            -d example.com`"

    ./do1.sh --email=someone@gmail.com \
             --managed \
             example.com
}

@test 'passes the email to simp_le if -e EMAIL is passed' {
    stub docker \
        "`docker_images_simp_le_cmd`" \
        "`docker_run_simp_le_cmd \
            --email someone@gmail.com \
            -d example.com`"

    ./do1.sh -e someone@gmail.com \
             --managed \
             example.com
}

@test 'passes 2 domains to simp_le' {
    stub docker \
        "`docker_images_simp_le_cmd`" \
        "`docker_run_simp_le_cmd \
            --email someone@gmail.com \
            -d example1.com \
            -d example2.com`"

    ./do1.sh --email someone@gmail.com \
             --managed \
             example1.com example2.com
}

@test 'runs a hook if --renew-hook CODE is passed' {
    stub docker \
        "`docker_images_simp_le_cmd`" \
        "`docker_run_simp_le_cmd \
            --email someone@gmail.com \
            -d example.com`"

    ./do1.sh --email someone@gmail.com \
             --managed \
             --renew-hook "touch ${BATS_TEST_TMPDIR@Q}/renew-hook" \
             example.com

    assert_file_exists "$BATS_TEST_TMPDIR"/renew-hook
}

@test 'runs a hook if --renew-hook=CODE is passed' {
    stub docker \
        "`docker_images_simp_le_cmd`" \
        "`docker_run_simp_le_cmd \
            --email someone@gmail.com \
            -d example.com`"

    ./do1.sh --email someone@gmail.com \
             --managed \
             --renew-hook="touch ${BATS_TEST_TMPDIR@Q}/renew-hook" \
             example.com

    assert_file_exists "$BATS_TEST_TMPDIR"/renew-hook
}

@test 'runs 2 hooks' {
    stub docker \
        "`docker_images_simp_le_cmd`" \
        "`docker_run_simp_le_cmd \
            --email someone@gmail.com \
            -d example.com`"

    ./do1.sh --email someone@gmail.com \
             --managed \
             --renew-hook "touch ${BATS_TEST_TMPDIR@Q}/renew-hook1" \
             --renew-hook "touch ${BATS_TEST_TMPDIR@Q}/renew-hook2" \
             example.com

    assert_file_exists "$BATS_TEST_TMPDIR"/renew-hook1
    assert_file_exists "$BATS_TEST_TMPDIR"/renew-hook2
}

@test 'exits with 2 if simp_le succeeds and a hook fails' {
    stub docker \
        "`docker_images_simp_le_cmd`" \
        "`docker_run_simp_le_cmd \
            --email someone@gmail.com \
            -d example.com`"

    run ./do1.sh --email someone@gmail.com \
                 --managed \
                 --renew-hook 'exit 1' \
                 example.com

    assert_equal "$status" 2
}

@test "doesn't run hooks and exits with 1 if simp_le exits with 1" {
    stub docker \
        "`docker_images_simp_le_cmd`" \
        "`docker_run_simp_le_cmd \
            --email someone@gmail.com \
            -d example.com \
            --exit-code 1`"

    run ./do1.sh --email someone@gmail.com \
                 --managed \
                 --renew-hook "touch ${BATS_TEST_TMPDIR@Q}/renew-hook" \
                 example.com

    assert_equal "$status" 1
    assert_file_not_exists "$BATS_TEST_TMPDIR"/renew-hook
}

@test "doesn't run hooks and exits with 2 if simp_le exits with 2" {
    stub docker \
        "`docker_images_simp_le_cmd`" \
        "`docker_run_simp_le_cmd \
            --email someone@gmail.com \
            -d example.com \
            --exit-code 2`"

    run ./do1.sh --email someone@gmail.com \
                 --managed \
                 --renew-hook "touch ${BATS_TEST_TMPDIR@Q}/renew-hook" \
                 example.com

    assert_equal "$status" 2
    assert_file_not_exists "$BATS_TEST_TMPDIR"/renew-hook
}

@test 'passes the staging server to simp_le if --staging is passed' {
    stub docker \
        "`docker_images_simp_le_cmd`" \
        "`docker_run_simp_le_cmd \
            --email someone@gmail.com \
            -d example.com \
            --server https://acme-staging-v02.api.letsencrypt.org/directory`"

    ./do1.sh --email someone@gmail.com \
             --managed --staging \
             example.com
}

@test 'passes the staging server to simp_le if -s is passed' {
    stub docker \
        "`docker_images_simp_le_cmd`" \
        "`docker_run_simp_le_cmd \
            --email someone@gmail.com \
            -d example.com \
            --server https://acme-staging-v02.api.letsencrypt.org/directory`"

    ./do1.sh --email someone@gmail.com \
             --managed -s \
             example.com
}

teardown() {
    unstub docker
    if [ "${ncat_pid-}" ]; then
        kill -- "$ncat_pid" 2>/dev/null || true
    fi
}
