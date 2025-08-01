FROM ubuntu:22.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies as specified in Fast DDS documentation
RUN apt-get update && apt-get install -y \
    btop \
    build-essential \
    cmake \
    curl \
    gdb \
    git \
    pkg-config \
    python3-dev \
    python3-pip \
    swig \
    tree \
    valgrind \
    vim \
    wget \
    xz-utils \
    # Fast DDS dependencies
    libasio-dev \
    libtinyxml2-dev \
    # OpenSSL for security features
    libssl-dev \
    # Security dependencies (Libp11 and SoftHSM)
    libp11-dev \
    softhsm2 \
    # Testing framework
    libgtest-dev \
    # XML validation
    libxml2-utils \
    && rm -rf /var/lib/apt/lists/*

# Build and install Fast DDS stack
RUN <<EOF
mkdir -p /opt/DDS
cd /opt/DDS

git clone https://github.com/eProsima/foonathan_memory_vendor.git
cmake -S foonathan_memory_vendor -B foonathan_memory_vendor/build \
    -DCMAKE_INSTALL_PREFIX=/usr/local/ -DBUILD_SHARED_LIBS=ON
cmake --build foonathan_memory_vendor/build --target install

git clone https://github.com/eProsima/Fast-CDR.git
cmake -S Fast-CDR -B Fast-CDR/build \
    -DCMAKE_INSTALL_PREFIX=/usr/local/ -DBUILD_SHARED_LIBS=ON
cmake --build Fast-CDR/build --target install

git clone https://github.com/eProsima/Fast-DDS.git
cmake -S Fast-DDS -B Fast-DDS/build \
    -DCMAKE_INSTALL_PREFIX=/usr/local/ -DBUILD_SHARED_LIBS=ON \
    -DSECURITY=ON -DCOMPILE_EXAMPLES=OFF -DBUILD_TESTING=OFF
cmake --build Fast-DDS/build --target install

# Update library cache
ldconfig
EOF

# install just command runner
RUN curl -LsSf https://just.systems/install.sh | bash -s -- --to /usr/local/bin

# Set up Go environment
RUN curl -L https://go.dev/dl/go1.24.5.linux-$(dpkg --print-architecture).tar.gz | tar -C /usr/local -xzf -
ENV PATH="/usr/local/go/bin:${PATH}"
ENV GOROOT="/usr/local/go"
ENV GOPATH="/go"

# Install Zig
RUN curl -L https://ziglang.org/download/0.14.1/zig-$(uname -m)-linux-0.14.1.tar.xz | tar -C /usr/local -xJf - && \
    ln -s /usr/local/zig-$(uname -m)-linux-*/zig /usr/local/bin/zig

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

CMD ["/bin/bash"]