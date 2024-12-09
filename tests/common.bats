setup() {
    load shared
    bats_load_library bats-support
    bats_load_library bats-assert
    bats_load_library bats-mock/stub.bash
    strict
    . common.sh
}

@test 'web_server_running: exits with 1 if no web server is running' {
    run strict web_server_running

    assert_equal "$status" 1
}

@test 'web_server_running: exits with 0 if a web server is running' {
    run_ncat_server localhost "$HTTPD_PORT"

    web_server_running
}

@test 'docker_pull: pulls the image if no image exists locally' {
    stub docker \
        'images -q -- whatamidoing : ' \
        'pull -- whatamidoing : '

    docker_pull whatamidoing
}

@test "docker_pull: doesn't pull the image if the image exists locally" {
    stub docker \
        'images -q -- whatamidoing : echo whatamidoing'

    docker_pull whatamidoing
}

@test 'docker_pull: outputs nothing on success' {
    stub docker \
        'images -q -- whatamidoing : ' \
        'pull -- whatamidoing : echo pulling...'

    run strict docker_pull whatamidoing

    assert_output ''
}

@test 'docker_pull: outputs the output on failure' {
    stub docker \
        'images -q -- whatamidoing : ' \
        'pull -- whatamidoing : echo error; exit 1'

    run strict docker_pull whatamidoing

    assert_output error
}

@test 'getvar: outputs the value from the file' {
    echo a=b > "$BATS_TEST_TMPDIR"/config

    run strict getvar "$BATS_TEST_TMPDIR"/config a

    assert_output b
}

@test "getvar: outputs nothing if the variable doesn't exist in the file" {
    touch -- "$BATS_TEST_TMPDIR"/config

    run strict getvar "$BATS_TEST_TMPDIR"/config a

    assert_output ''
}

@test "getvar: outputs nothing if the variable is set but doesn't exist in the file" {
    touch -- "$BATS_TEST_TMPDIR"/config
    a=b

    run strict getvar "$BATS_TEST_TMPDIR"/config a

    assert_output ''
}

@test 'getvar: handles values with spaces' {
    echo "a='b  c'" > "$BATS_TEST_TMPDIR"/config

    run strict getvar "$BATS_TEST_TMPDIR"/config a

    assert_output 'b  c'
}

@test 'getarr: sets the variable from the file' {
    echo 'a=(b)' > "$BATS_TEST_TMPDIR"/config

    getarr "$BATS_TEST_TMPDIR"/config a

    assert_equal ${#a[*]} 1
    assert_equal "${a[0]}" b
}

@test 'getarr: sets the variable from the file (2 elements)' {
    echo 'a=(b c)' > "$BATS_TEST_TMPDIR"/config

    getarr "$BATS_TEST_TMPDIR"/config a

    assert_equal ${#a[*]} 2
    assert_equal "${a[0]}" b
    assert_equal "${a[1]}" c
}

@test "getarr: sets the variable to an empty array if the variable doesn't exist in the file" {
    touch -- "$BATS_TEST_TMPDIR"/config

    getarr "$BATS_TEST_TMPDIR"/config a

    assert_equal ${#a[*]} 0
}

@test "getarr: resets the variable to an empty array if the variable is set but doesn't exists in the file" {
    touch -- "$BATS_TEST_TMPDIR"/config
    a=(b)

    getarr "$BATS_TEST_TMPDIR"/config a

    assert_equal ${#a[*]} 0
}

@test 'getarr: handles elements with spaces' {
    echo "a=('b  c')" > "$BATS_TEST_TMPDIR"/config

    getarr "$BATS_TEST_TMPDIR"/config a

    assert_equal ${#a[*]} 1
    assert_equal "${a[0]}" 'b  c'
}

@test "getarr: doesn't introduce extra variables" {
    ml 'a=(b)' \
       'b=c' \
       > "$BATS_TEST_TMPDIR"/config

    getarr "$BATS_TEST_TMPDIR"/config a

    assert_equal "${b-unset}" unset
}

@test 'quiet: outputs nothing on success' {
    stub whatever \
        'echo stdout; echo stderr >&2'

    run strict quiet whatever

    assert_equal "$status" 0
    assert_output ''
}

@test 'quiet: outputs the output on failure' {
    stub whatever \
        'echo stdout; echo stderr >&2; exit 1'

    run strict quiet whatever

    assert_equal "$status" 1
    assert_output $'stdout\nstderr'
}

teardown() {
    unstub docker
    unstub whatever
    if [ "${ncat_pid-}" ]; then
        kill -- "$ncat_pid" 2>/dev/null || true
    fi
}
