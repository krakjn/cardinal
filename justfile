#!/usr/bin/env just --justfile
_:
  just --list


image:
    docker build -t cardinal - < Dockerfile

_mkdirs:
    @mkdir -p .cache/{go,zig,rust}

DOCKER_RUN := "docker run --rm --tty -v $(pwd):/workspace -v $(pwd)/.cache/go:/root/.cache/go -v $(pwd)/.cache/zig:/root/.cache/zig -v $(pwd)/.cache/rust:/root/.cargo/registry -w /workspace cardinal"

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
    cd rust
    cargo run

run ARG:
    docker run --rm -it \
        -v $(pwd):/workspace \
        -v $(pwd)/.cache/go:/root/.cache/go \
        -v $(pwd)/.cache/zig:/root/.cache/zig \
        -v $(pwd)/.cache/rust:/root/.cargo/registry \
        -w /workspace \
        cardinal \
        just _{{ ARG }}-run

shell:
    docker run --rm -it \
        -v $(pwd):/workspace \
        -v $(pwd)/.cache/go:/root/.cache/go \
        -v $(pwd)/.cache/zig:/root/.cache/zig \
        -v $(pwd)/.cache/rust:/root/.cargo/registry \
        -w /workspace \
        cardinal \
        bash

clean:
    rm -rf build/
    rm -rf go/build/
    rm -rf zig/zig-out/
    rm -rf rust/target/

# Clean up docker resources
clean-docker:
    docker-compose down --remove-orphans
    docker system prune -f