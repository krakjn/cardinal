#!/usr/bin/env just --justfile

_:
  just --list

image:
    docker build -t cardinal - < Dockerfile

# Build with real Fast DDS
build:
    mkdir -p .cache
    docker run --rm \
        -v $(pwd):/workspace \
        -v $(pwd)/.cache:/go/pkg \
        -w /workspace \
        cardinal \
        just _compile

_compile:
    #!/bin/bash
    set -e
    mkdir -p build
    g++ -I/usr/local/include -std=c++17 -fPIC -c fastdds.cpp -o build/fastdds.o
    ar rcs build/libfastdds_wrapper.a build/fastdds.o
    CGO_CFLAGS="" go build -o build/cardinal .

# Run the application
run *ARGS:
    docker run --rm -it \
        -v $(pwd):/workspace \
        -v $(pwd)/.cache:/go/pkg \
        -w /workspace \
        cardinal \
        {{ if ARGS == "" { "./build/cardinal" } else { ARGS } }}

shell:
    docker-compose run --rm cardinal bash

# Clean up build artifacts
clean:
    rm -rf build/

# Clean up docker resources
clean-docker:
    docker-compose down --remove-orphans
    docker system prune -f