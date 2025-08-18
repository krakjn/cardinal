#!/usr/bin/env just --justfile
set windows-shell := ["powershell.exe", "-NoLogo", "-Command"]
CWD := source_directory()

_:
  just --list


image:
    docker build -t cardinal .


build: _fastdds _lib

_fastdds:
    #!/usr/bin/env bash
    echo "🔨 Building FastDDS with CMake..."
    mkdir -p install
    
    # Build Fast-CDR first
    cmake -B build/fastcdr -S Fast-CDR -G Ninja \
        -DCMAKE_INSTALL_PREFIX=install \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
    cmake --build build/fastcdr --target install --parallel
    
    # Build FastDDS (depends on Fast-CDR)
    cmake -B build/fastdds -S Fast-DDS -G Ninja \
        -DCMAKE_INSTALL_PREFIX=install \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -Dfastcdr_DIR=install/lib/cmake/fastcdr
    cmake --build build/fastdds --target install --parallel

_lib:
    #!/usr/bin/env bash
    echo "🔨 Building Cardinal wrapper with Zig..."
    mkdir -p .cache/zig build
    zig build lib --cache-dir .cache/zig
    # Copy our header to install directory
    cp lib/fastdds.h install/include/

# Go build targets
go-fastdds: build
    #!/usr/bin/env bash
    echo "🔨 Building Go app with FastDDS support..."
    cd go && mkdir -p build
    go build -tags fastdds -o build/cardinal .

go-mock:
    #!/usr/bin/env bash
    echo "🔨 Building Go app (mock-only)..."
    cd go && mkdir -p build
    go build -o build/cardinal .

# Run targets
run-fastdds: go-fastdds
    echo "🚀 Running Cardinal with FastDDS..."
    ./go/build/cardinal

run-mock: go-mock
    echo "🚀 Running Cardinal with mock DDS..."
    ./go/build/cardinal

# Quick development cycle
dev: go-mock
    ./go/build/cardinal

clean:
    #!/usr/bin/env bash
    echo "🧹 Cleaning build artifacts..."
    rm -rf .cache/
    rm -rf build/
    rm -rf go/build/
    rm -rf install/

# Clean everything including Docker
clean-all: clean clean-docker

# Clean up docker resources
clean-docker:
    #!/usr/bin/env bash
    echo "🧹 Cleaning Docker resources..."
    docker-compose down --remove-orphans || true
    docker system prune -f