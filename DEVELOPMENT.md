# Fast DDS Development Guide

This guide shows how to develop Go applications with Fast DDS using our hermetic Docker environment.

> **📋 Note**: This project now uses [`just`](https://github.com/casey/just) for command running.  
> Install with: `cargo install just` or see [installation guide](https://github.com/casey/just#installation)

## Quick Start

### 1. Show Available Commands
```bash
# See all available commands
just --list

# See detailed examples  
just examples

# Show environment info
just info
```

### 2. Build the Development Environment
```bash
# Build the hermetic Fast DDS environment (one time setup)
just dev-image
```

### 3. Start Development Shell
```bash
# Mount current directory and start interactive shell
just dev-shell
```

You'll see a welcome message and be dropped into a shell with:
- 🚀 Fast DDS fully installed and configured
- 🐹 Go 1.21 ready with CGO enabled  
- 📁 Your code mounted at `/workspace`
- 🔧 All development tools available

### 3. Inside the Development Shell
```bash
# Your code is already here!
ls -la

# Go module commands work normally
go mod init myproject
go mod tidy

# Build with Fast DDS (if you have C++ wrapper)
g++ -I/opt/fastdds/include -std=c++14 -fPIC -c fastdds.cpp -o fastdds.o
ar rcs libfastdds_wrapper.a fastdds.o

# Build your Go application
go build -o myapp *.go

# Run it!
./myapp
```

### 4. One-Command Workflows

Instead of interactive shell, you can use one-command workflows:

```bash
# Build your application
just dev-build                   # Builds 'cardinal' binary
just dev-build myapp             # Custom binary name

# Run your application  
just dev-run                     # Runs 'cardinal'
just dev-run myapp               # Custom binary name

# Build and run in one command
just dev-cycle                   # Build and run 'cardinal'
just dev-cycle myapp             # Build and run 'myapp'
```

## Development Patterns

### Pattern 1: Interactive Development
```bash
# Start shell and stay in it for development
just dev-shell

# Inside container:
go mod tidy
go build -o myapp *.go
./myapp

# Make changes, rebuild, test - all in same environment
```

### Pattern 2: Build-Run Cycle
```bash
# Make changes to your code
vim main.go

# Build and run in one command
just dev-cycle

# Or separate steps
just dev-build
just dev-run
```

### Pattern 3: Docker Compose Development
```bash
# Start long-running development container
just compose-dev

# Exec into it for development
docker exec -it fastdds-development bash

# Build using compose
just compose-build
```

## Environment Details

### What's Installed
- **Fast DDS**: Complete eProsima Fast DDS stack
- **Fast CDR**: Serialization library
- **Fast DDS-Gen**: IDL to code generator (Java-based)
- **Python Bindings**: Fast DDS Python support
- **Security**: OpenSSL, PKCS#11, SoftHSM2
- **Go 1.21**: With CGO properly configured
- **Development Tools**: vim, nano, gdb, valgrind, htop

### Environment Variables
```bash
FASTDDS_PREFIX="/opt/fastdds"
CGO_ENABLED=1
CGO_CPPFLAGS="-I/opt/fastdds/include"  
CGO_LDFLAGS="-L/opt/fastdds/lib -lfastrtps -lfastcdr -lstdc++"
```

### Mounted Volumes
- `./` → `/workspace` (your source code)
- Go module cache (persisted)
- Go build cache (persisted)

## Testing Multi-Process DDS

### Start Multiple Instances
```bash
# Terminal 1: Start publisher
just dev-shell
# Inside: ./myapp --mode=publisher

# Terminal 2: Start subscriber  
just dev-shell
# Inside: ./myapp --mode=subscriber

# Or use automated testing
just test-discovery        # Test with 2 instances
just test-discovery 5      # Test with 5 instances
```

They'll discover each other automatically via DDS multicast!

### Docker Network Testing
```bash
# Start multiple containers
docker run -it --rm --network host --name dds1 -v $(pwd):/workspace:rw fastdds-dev:latest
docker run -it --rm --network host --name dds2 -v $(pwd):/workspace:rw fastdds-dev:latest

# They can communicate via DDS across containers
```

## Tips and Tricks

### Persistent Development Container
```bash
# Start a named container for longer development sessions
docker run -it --name my-fastdds-dev \
  --network host \
  -v $(pwd):/workspace:rw \
  -v fastdds-go-mod-cache:/go/pkg/mod \
  fastdds-dev:latest

# Later, restart the same container
docker start -ai my-fastdds-dev
```

### Debugging with GDB
```bash
# Build with debug symbols
go build -gcflags="all=-N -l" -o myapp *.go

# Debug in the environment
make dev-shell
# Inside: gdb ./myapp
```

### Multiple Go Projects
```bash
# Use the same environment for different projects
cd /path/to/project1 && make dev-shell
cd /path/to/project2 && make dev-shell
```

### IDE Integration
Many IDEs can be configured to use this Docker environment for builds and runs, providing full Fast DDS integration in your development workflow.

## Troubleshooting

### Common Issues
1. **Permission issues**: The container runs as `developer` user (UID 1000)
2. **Network issues**: Use `--network host` for DDS multicast
3. **Build cache**: Clear with `make dev-clean` if needed

### Rebuilding Environment
```bash
# Clean everything and rebuild
just dev-clean
just dev-image

# Or clean everything (including legacy resources)
just dev-clean && just prod-clean
```

This hermetic approach gives you a consistent, reproducible Fast DDS development environment that works identically across different machines and operating systems! 