#!/usr/bin/env just --justfile
set windows-shell := ["powershell.exe", "-NoLogo", "-Command"]
CWD := source_directory()

_:
  just --list


image:
    docker build -t cardinal .

_mkdirs:
    @mkdir -p .cache/{go,zig,rust}

DOCKER_RUN := "docker run --rm --tty -v {{ CWD }}:/workspace -v {{ CWD }}/.cache/go:/root/.cache/go -v {{ CWD }}/.cache/zig:/root/.cache/zig -v {{ CWD }}/.cache/rust:/root/.cargo/registry -w /workspace cardinal"

build ARG='all': _mkdirs
    #!/usr/bin/env bash
    if [ "{{ ARG }}" = "all" ]; then
        {{ DOCKER_RUN }} just _lib _go _zig _rust
    else
        {{ DOCKER_RUN }} just _{{ ARG }}
    fi

_lib:
    mkdir -p build
    g++ -I/usr/local/include -std=c++17 -fPIC -c lib/fastdds.cpp -o build/fastdds.o
    ar rcs build/libcardinal-fastdds.a build/fastdds.o

_go:
    #!/usr/bin/env bash
    cd go
    mkdir -p build
    CGO_CFLAGS="" CGO_CXXFLAGS="-std=c++17" go build -o build/cardinal .

_go-run:
    ./go/build/cardinal

_zig:
    cd zig && zig build --cache-dir .cache/zig

_zig-run:
    #!/usr/bin/env bash
    ./zig/zig-out/bin/cardinal

_rust:
    #!/usr/bin/env bash
    . /root/.cargo/env
    cd rust 
    cargo build --release

_rust-run:
    #!/usr/bin/env bash
    ./rust/target/release/cardinal

run ARG:
    docker run --rm -it \
        -v {{ CWD }}:/workspace \
        -v {{ CWD }}/.cache/go:/root/.cache/go \
        -v {{ CWD }}/.cache/zig:/root/.cache/zig \
        -v {{ CWD }}/.cache/rust:/root/.cargo/registry \
        -w /workspace \
        cardinal \
        just _{{ ARG }}-run

shell:
    docker run --rm -it \
        -v {{ CWD }}:/workspace \
        -v {{ CWD }}/.cache/go:/root/.cache/go \
        -v {{ CWD }}/.cache/zig:/root/.cache/zig \
        -v {{ CWD }}/.cache/rust:/root/.cargo/registry \
        -w /workspace \
        cardinal \
        bash

clean:
    rm -rf .cache/
    rm -rf build/
    rm -rf go/build/
    rm -rf zig/{zig-out,.cache,.zig-cache}
    rm -rf rust/target/

# Clean up docker resources
clean-docker:
    docker-compose down --remove-orphans
    docker system prune -f