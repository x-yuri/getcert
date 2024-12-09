setup() {
    load shared
    bats_load_library bats-support
    bats_load_library bats-assert
    strict
}

@test 'the web server serves the files' {
    cid=`./httpd.sh`
    wait4port localhost "$HTTPD_PORT"

    docker exec -- "$cid" sh -c 'echo a > a'
    run curl -sS localhost:"$HTTPD_PORT"/a
    assert_output a
}

@test 'the web server uses the getcert volume' {
    cid=`./httpd.sh`
    wait4port localhost "$HTTPD_PORT"

    docker run --rm -v getcert:/docroot alpine:3.20 sh -c 'echo a > docroot/a'
    run curl -sS localhost:"$HTTPD_PORT"/a
    assert_output a
}

teardown() {
    docker stop -- "$cid"
}
