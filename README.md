# `getcert`

Obtains certificates on a server where there's a running web server or where there isn't.

Prerequisites: `bash`, `docker`.

## Usage

Create a config at `~/.getcert`:

```
email=my.email@gmail.com  # required
docroot=/path/to/docroot
```

`docroot` is needed when there's a running web server. The web server should serve `/.well-known` requests using the files in `docroot`.

Each certificate needs a file in `~/.getcert.d/NAME`:

```
domains=(example.com)  # at least one domain is required
staging=1
renew_hooks=('systemctl webserver reload')
```

To obtain certificates:

```
$ path/to/getcert/do.sh
```

## Running tests

Prerequisites: [`ncat`][a], [`wait4ports`][b] or [`wait-for-it`][c], [`bats-support`][d], [`bats-assert`][e], [`bats-file`][f], [`jasonkarns/bats-mock`][g].

```
$ bats tests
```

`bats` libraries are looked in `~/.bats/lib` and `/usr/lib/bats`. The library path can be overriden with [`BATS_LIB_PATH`][h].

Some tests start a web server on port 1024. The port can be overriden with `HTTPD_PORT`.

To run them in a `docker` container:

```
$ docker run --rm -it \
    -v "$PWD":/app \
    -w /app \
    -v /run/docker.sock:/run/docker.sock \
    --network host \
    -e ALLOW_CHANGING_ETC=1 \
    alpine:3.21
/app # apk add git bash ncurses nmap-ncat docker wait4ports
/app # git clone https://github.com/bats-core/bats-core ~/.bats
/app # git clone https://github.com/bats-core/bats-support ~/.bats/lib/bats-support
/app # git clone https://github.com/bats-core/bats-assert ~/.bats/lib/bats-assert
/app # git clone https://github.com/bats-core/bats-file ~/.bats/lib/bats-file
/app # git clone https://github.com/jasonkarns/bats-mock ~/.bats/lib/bats-mock
/app # ~/.bats/bin/bats tests
```

[a]: https://nmap.org/
[b]: https://github.com/erikogan/wait4ports
[c]: https://github.com/vishnubob/wait-for-it
[d]: https://github.com/bats-core/bats-support
[e]: https://github.com/bats-core/bats-assert
[f]: https://github.com/bats-core/bats-file
[g]: https://github.com/jasonkarns/bats-mock
[h]: https://bats-core.readthedocs.io/en/stable/writing-tests.html#bats-load-library-load-system-wide-libraries
