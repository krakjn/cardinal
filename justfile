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

# Native development commands (no Docker)
native-lib:
    #!/usr/bin/env bash
    echo "🔨 Building FastDDS libraries natively with Zig..."
    mkdir -p install/include install/lib
    zig build lib

native-go:
    #!/usr/bin/env bash
    echo "🔨 Building Go app natively with FastDDS support..."
    cd go && go build -tags fastdds -o build/cardinal .

native-go-mock:
    #!/usr/bin/env bash
    echo "🔨 Building Go app natively (mock-only)..."
    cd go && go build -o build/cardinal .

native-all: native-lib native-go
    echo "✅ Native build complete!"

native-demo: native-go-mock
    echo "🚀 Running Cardinal with enhanced TUI..."
    ./go/build/cardinal

_lib:
    #!/usr/bin/env bash
    # Build FastDDS and Cardinal library using Zig natively
    mkdir -p install/include install/lib
    zig build lib --cache-dir .cache/zig
    echo "✅ Built FastDDS libraries to install/ directory"

_go:
    #!/usr/bin/env bash
    cd go
    mkdir -p build
    # Build with FastDDS support using our local libraries
    go build -tags fastdds -o build/cardinal .

_go-mock:
    #!/usr/bin/env bash
    cd go
    mkdir -p build
    # Build without FastDDS (mock-only version for quick development)
    go build -o build/cardinal .

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