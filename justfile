# Cardinal - Fast DDS + Go Development
# Modern command runner for development workflows

# Default recipe - show help
_:
    @just --list

# Variables
app_name := "cardinal"
dev_image := "fastdds-dev:latest"
prod_image := "cardinal:latest"

# Fast DDS paths (updated for new Dockerfile)
fastdds_prefix := "/usr/local"

# =============================================================================
# Development Targets (Hermetic Fast DDS Environment)
# =============================================================================

# Build the hermetic Fast DDS development environment
dev-image:
    @echo "🔨 Building hermetic Fast DDS development environment..."
    docker build -t {{dev_image}} .
    @echo "✅ Development environment ready!"

# Start interactive development shell with current directory mounted
dev-shell:
    @echo "🚀 Starting Fast DDS Development Environment..."
    @just _check-docker
    @just _ensure-dev-image
    @echo "📂 Mounting current directory: {{justfile_directory()}}"
    @echo "🔧 Starting development shell..."
    docker run \
        --rm \
        -it \
        --name fastdds-dev-shell \
        --network host \
        -v "{{justfile_directory()}}:/workspace:rw" \
        -e TERM=xterm-256color \
        -e FASTDDS_DEFAULT_PROFILES_FILE=/workspace/fastdds_profiles.xml \
        -w /workspace \
        {{dev_image}} \
        /bin/bash
    @echo "✅ Development session ended."

# Build Go application in Fast DDS environment
dev-build target=app_name:
    @echo "🔨 Building Go application in Fast DDS environment..."
    @just _check-docker
    @just _ensure-dev-image
    @echo "📂 Building from: {{justfile_directory()}}"
    @echo "🎯 Target: {{target}}"
    docker run --rm \
        -v "{{justfile_directory()}}:/workspace:rw" \
        -w /workspace \
        {{dev_image}} \
        bash -c 'echo "🔍 Checking Go module..."; if [ ! -f go.mod ]; then echo "❌ No go.mod found. Please run: just init <module-name>"; exit 1; fi; echo "📦 Downloading dependencies..."; go mod tidy; echo "🚀 Building Go application (mock DDS)..."; go build -o {{target}} main.go; echo "✅ Build complete!"; ls -la {{target}}'
    @echo "🎉 Build successful! Run with: just dev-run {{target}}"

# Build Go application with real Fast DDS
dev-build-real target=app_name:
    @echo "🔨 Building Go application with real Fast DDS..."
    @just _check-docker
    @just _ensure-dev-image
    @echo "📂 Building from: {{justfile_directory()}}"
    @echo "🎯 Target: {{target}}"
    docker run --rm \
        -v "{{justfile_directory()}}:/workspace:rw" \
        -w /workspace \
        -e CGO_ENABLED=1 \
        -e CGO_CPPFLAGS="-I{{fastdds_prefix}}/include" \
        -e CGO_LDFLAGS="-L{{fastdds_prefix}}/lib -lfastrtps -lfastcdr -lstdc++" \
        {{dev_image}} \
        bash -c 'echo "🔍 Checking Go module..."; if [ ! -f go.mod ]; then echo "❌ No go.mod found. Please run: just init <module-name>"; exit 1; fi; echo "📦 Downloading dependencies..."; go mod tidy; if [ -f fastdds.cpp ]; then echo "🔧 Building C++ wrapper..."; g++ -I{{fastdds_prefix}}/include -std=c++17 -fPIC -c fastdds.cpp -o fastdds.o && ar rcs libfastdds_wrapper.a fastdds.o && echo "✅ C++ wrapper built"; fi; echo "🚀 Building Go application..."; go build -o {{target}} *.go; echo "✅ Build complete!"; ls -la {{target}}'
    @echo "🎉 Build successful! Run with: just dev-run {{target}}"

# Run Go application in Fast DDS environment
dev-run binary=app_name *args="":
    @echo "🚀 Running {{binary}} in Fast DDS environment..."
    @just _check-binary {{binary}}
    @just _check-docker
    @just _ensure-dev-image
    @echo "📂 Running from: {{justfile_directory()}}"
    @echo "🎯 Executing: {{binary}} {{args}}"
    docker run \
        --rm \
        -it \
        --name fastdds-app-runner \
        --network host \
        -v "{{justfile_directory()}}:/workspace:rw" \
        -e TERM=xterm-256color \
        -e FASTDDS_DEFAULT_PROFILES_FILE=/workspace/fastdds_profiles.xml \
        -w /workspace \
        {{dev_image}} \
        ./{{binary}} {{args}}
    @echo "✅ Application finished."

# Full development cycle: build and run
dev-cycle target=app_name *args="":
    @just dev-build {{target}}
    @just dev-run {{target}} {{args}}

# Clean development resources
dev-clean:
    @echo "🧹 Cleaning development resources..."
    -docker stop fastdds-dev-shell 2>/dev/null || true
    -docker stop fastdds-app-runner 2>/dev/null || true
    -docker rmi {{dev_image}} 2>/dev/null || true
    -docker volume rm fastdds-go-mod-cache 2>/dev/null || true
    -docker volume rm fastdds-go-build-cache 2>/dev/null || true
    @echo "✅ Development environment cleaned."

# =============================================================================
# Docker Compose Development
# =============================================================================

# Start long-running development container via compose
compose-dev:
    @echo "🐳 Starting development container with docker-compose..."
    docker-compose -f docker-compose.dev.yml up -d fastdds-dev
    @echo "✅ Development container running. Access with: docker exec -it fastdds-development bash"

# Build application using compose build service
compose-build:
    @echo "🔨 Building with docker-compose..."
    docker-compose -f docker-compose.dev.yml run --rm fastdds-build

# Stop development compose services
compose-down:
    @echo "🛑 Stopping development services..."
    docker-compose -f docker-compose.dev.yml down

# View compose logs
compose-logs:
    docker-compose -f docker-compose.dev.yml logs -f cardinal

# =============================================================================
# Multi-Instance Testing (DDS Discovery)
# =============================================================================

# Test DDS discovery with multiple instances
test-discovery instances="2":
    @echo "🔍 Testing DDS discovery with {{instances}} instances..."
    @just _ensure-dev-image
    @just dev-build {{app_name}}
    @echo "🚀 Starting {{instances}} DDS instances..."
    @for i in $(seq 1 {{instances}}); do \
        echo "  Starting instance $$i..."; \
        docker run -d \
            --name "dds-test-$$i" \
            --network host \
            -v "{{justfile_directory()}}:/workspace:rw" \
            -e FASTDDS_DEFAULT_PROFILES_FILE=/workspace/fastdds_profiles.xml \
            -w /workspace \
            {{dev_image}} \
            ./{{app_name}} > /dev/null; \
    done
    @echo "⏳ Running for 30 seconds..."
    @sleep 30
    @echo "📊 Checking logs..."
    @for i in $(seq 1 {{instances}}); do \
        echo "--- Instance $$i logs ---"; \
        docker logs "dds-test-$$i" | tail -5; \
    done
    @echo "🧹 Cleaning up..."
    @for i in $(seq 1 {{instances}}); do \
        docker stop "dds-test-$$i" > /dev/null 2>&1; \
        docker rm "dds-test-$$i" > /dev/null 2>&1; \
    done
    @echo "✅ Discovery test complete!"

# =============================================================================
# Legacy Production Targets (Original App-Bundled Image)
# =============================================================================

# Build legacy production image (app bundled in image)
prod-build:
    @echo "🏗️ Building legacy production image..."
    @echo "⚠️  Note: Consider using dev-* targets for better workflow"
    docker build -t {{prod_image}} -f Dockerfile.legacy .

# Run legacy production image
prod-run:
    @echo "🚀 Running legacy production image..."
    docker run --rm -it --network host {{prod_image}}

# Clean legacy production resources
prod-clean:
    @echo "🧹 Cleaning legacy production resources..."
    -docker stop cardinal-running 2>/dev/null || true
    -docker rm cardinal-running 2>/dev/null || true
    -docker rmi {{prod_image}} 2>/dev/null || true

# =============================================================================
# Go Development Helpers
# =============================================================================

# Initialize new Go module
init module-name:
    @echo "🚀 Initializing Go module: {{module-name}}"
    go mod init {{module-name}}
    @echo "✅ Go module initialized. Run 'just dev-shell' to develop with Fast DDS."

# Run Go tests in Fast DDS environment
test:
    @echo "🧪 Running tests in Fast DDS environment..."
    @just _ensure-dev-image
    docker run \
        --rm \
        -v "{{justfile_directory()}}:/workspace:rw" \
        -w /workspace \
        -e CGO_ENABLED=1 \
        -e CGO_CPPFLAGS="-I{{fastdds_prefix}}/include" \
        -e CGO_LDFLAGS="-L{{fastdds_prefix}}/lib -lfastrtps -lfastcdr -lstdc++" \
        {{dev_image}} \
        go test -v ./...

# Format Go code
fmt:
    @echo "🎨 Formatting Go code..."
    go fmt ./...

# Lint Go code (if golangci-lint is available)
lint:
    @echo "🔍 Linting Go code..."
    @just _ensure-dev-image
    docker run \
        --rm \
        -v "{{justfile_directory()}}:/workspace:rw" \
        -w /workspace \
        -e CGO_ENABLED=1 \
        -e CGO_CPPFLAGS="-I{{fastdds_prefix}}/include" \
        -e CGO_LDFLAGS="-L{{fastdds_prefix}}/lib -lfastrtps -lfastcdr -lstdc++" \
        {{dev_image}} \
        bash -c "if command -v golangci-lint >/dev/null; then golangci-lint run; else echo '⚠️ golangci-lint not available'; fi"

# =============================================================================
# Utility Functions
# =============================================================================

# Check if Docker is running
_check-docker:
    @if ! docker info >/dev/null 2>&1; then \
        echo "❌ Docker is not running. Please start Docker first."; \
        exit 1; \
    fi

# Ensure development image exists
_ensure-dev-image:
    @if ! docker images {{dev_image}} | grep -q fastdds-dev; then \
        echo "🔨 Building Fast DDS development image..."; \
        just dev-image; \
    fi

# Check if binary exists
_check-binary binary:
    @if [ ! -f "{{binary}}" ]; then \
        echo "❌ Binary {{binary}} not found. Build it first with:"; \
        echo "   just dev-build {{binary}}"; \
        exit 1; \
    fi

# =============================================================================
# Information and Help
# =============================================================================

# Show environment information
info:
    @echo "📋 Cardinal Development Environment Information"
    @echo "=============================================="
    @echo "Project Directory: {{justfile_directory()}}"
    @echo "App Name: {{app_name}}"
    @echo "Dev Image: {{dev_image}}"
    @echo "Prod Image: {{prod_image}}"
    @echo "Fast DDS Prefix: {{fastdds_prefix}}"
    @echo ""
    @echo "🐳 Docker Status:"
    @docker --version 2>/dev/null || echo "  ❌ Docker not available"
    @docker-compose --version 2>/dev/null || echo "  ❌ Docker Compose not available"
    @if docker info >/dev/null 2>&1; then echo "  ✅ Docker is running"; else echo "  ❌ Docker is not running"; fi
    @echo ""
    @echo "🎯 Available Images:"
    @docker images | grep -E "(fastdds-dev|cardinal)" || echo "  No Cardinal images found"
    @echo ""
    @echo "📁 Go Module Status:"
    @if [ -f go.mod ]; then echo "  ✅ go.mod exists"; else echo "  ❌ No go.mod found - run 'just init <module-name>'"; fi
    @echo ""
    @echo "🚀 Quick Start:"
    @echo "  just dev-image    # Build development environment"
    @echo "  just dev-shell    # Start development shell"
    @echo "  just dev-build    # Build your application"
    @echo "  just dev-run      # Run your application"

# Show development workflow examples
examples:
    @echo "📖 Cardinal Development Examples"
    @echo "================================"
    @echo ""
    @echo "🏗️ First Time Setup:"
    @echo "  just init my-dds-app     # Initialize Go module"
    @echo "  just dev-image           # Build Fast DDS environment"
    @echo ""
    @echo "💻 Interactive Development:"
    @echo "  just dev-shell           # Start development shell"
    @echo "  # Inside shell: go build -o myapp *.go && ./myapp"
    @echo ""
    @echo "⚡ Quick Build-Run Cycle:"
    @echo "  just dev-cycle           # Build and run cardinal"
    @echo "  just dev-cycle myapp     # Build and run custom app"
    @echo ""
    @echo "🔍 Multi-Instance Testing:"
    @echo "  just test-discovery      # Test with 2 instances"
    @echo "  just test-discovery 5    # Test with 5 instances"
    @echo ""
    @echo "🐳 Docker Compose Workflow:"
    @echo "  just compose-dev         # Long-running dev container"
    @echo "  just compose-build       # One-off build"
    @echo "  just compose-down        # Stop services"
    @echo ""
    @echo "🧪 Testing and Quality:"
    @echo "  just test                # Run tests in DDS environment"
    @echo "  just fmt                 # Format code"
    @echo "  just lint                # Lint code"
    @echo ""
    @echo "🧹 Cleanup:"
    @echo "  just dev-clean           # Clean development resources"
    @echo "  just prod-clean          # Clean production resources" 