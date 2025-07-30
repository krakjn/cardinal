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

# Set up Go environment
RUN curl -L https://go.dev/dl/go1.24.5.linux-amd64.tar.gz | tar -C /usr/local -xzf -
ENV PATH="/usr/local/go/bin:${PATH}"
ENV GOROOT="/usr/local/go"
ENV GOPATH="/go"

RUN python3 -m pip install -U colcon-common-extensions vcstool

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

EOF

# Update library cache
RUN ldconfig

# Set up CGO environment for Fast DDS
ENV CGO_ENABLED=1
ENV CGO_CPPFLAGS="-I/usr/local/include"
ENV CGO_LDFLAGS="-L/usr/local/lib -lfastrtps -lfastcdr -lstdc++"

# Create development user
RUN useradd -m -s /bin/bash -u 1000 developer && \
    usermod -aG sudo developer && \
    echo "developer ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Create workspace directory
RUN mkdir -p /workspace && \
    chown -R developer:developer /workspace

# Switch to development user
USER developer

# Set workspace as working directory
WORKDIR /workspace

# Create welcome script
RUN echo '#!/bin/bash\n\
echo "🚀 Fast DDS Development Environment (Streamlined)"\n\
echo "==============================================="\n\
echo "Go Version: $(go version)"\n\
echo "Fast DDS: Installed to /usr/local"\n\
echo "CGO: Enabled and configured"\n\
echo ""\n\
echo "📁 Workspace: /workspace (mount your code here)"\n\
echo "🔧 Ready for: go build, CGO compilation"\n\
echo ""\n\
echo "Quick start:"\n\
echo "  go mod tidy"\n\
echo "  go build -o myapp *.go"\n\
echo "  ./myapp"\n\
echo ""\n\
echo "🎯 Ready for development!"\n\
' > /home/developer/.welcome.sh && \
    chmod +x /home/developer/.welcome.sh

# Add welcome message to bashrc
RUN echo 'bash /home/developer/.welcome.sh' >> /home/developer/.bashrc

# Expose DDS ports
EXPOSE 7400-7500/udp
EXPOSE 7400-7500/tcp

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD [ -f /usr/local/lib/libfastrtps.so ] || exit 1

# Default command - interactive shell for development
CMD ["/bin/bash"]

# Labels for documentation
LABEL maintainer="Fast DDS Development Team"
LABEL description="Streamlined Fast DDS development environment for Go applications"
LABEL version="2.0"
LABEL fast-dds-version="latest"
LABEL purpose="development-environment"
