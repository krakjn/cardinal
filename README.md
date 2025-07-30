# Cardinal - Go + Fast DDS + Lipgloss TUI Demo

A demonstration application that combines:
- **Go programming language**
- **Fast DDS** for real-time communication
- **Lipgloss** for beautiful terminal UI styling
- **Bubble Tea** for TUI framework
- **Multi-threading** with goroutines

> **⚡ Modern Development**: This project now uses [`just`](https://github.com/casey/just) for streamlined command running.  
> Install: `cargo install just` or see [installation guide](https://github.com/casey/just#installation)

## Features

- Two concurrent threads:
  1. **Publisher Thread**: Prints "Hello World" messages every 2 seconds
  2. **TUI Thread**: Displays received DDS messages in a beautiful terminal interface
- DDS communication between threads
- Graceful shutdown handling
- Beautiful styling with Lipgloss

## Why DDS? Understanding the Brokerless Architecture

### **DDS is Truly Brokerless** 🚀

Unlike traditional message brokers (RabbitMQ, Kafka, MQTT), DDS operates **peer-to-peer**:

- ✅ **No Central Server**: Participants communicate directly
- ✅ **Automatic Discovery**: Uses multicast to find other participants  
- ✅ **Direct Data Flow**: Publishers send directly to subscribers
- ✅ **Zero Single Point of Failure**: No broker to go down
- ✅ **High Performance**: No message routing overhead

### **How Discovery Works:**
1. **Multicast Announcement**: "Hey, I'm a publisher of HelloWorld messages!"
2. **Automatic Response**: "Great! I'm a subscriber, let's connect directly!"
3. **Peer-to-Peer Connection**: Direct communication established
4. **No Intermediary**: Data flows directly between applications

### **When You Might See "Discovery Server":**
The optional Discovery Server in our Docker setup is **NOT a broker**:
- ❌ **Not for message routing**: Data still flows peer-to-peer
- ✅ **Only for discovery help**: In complex networks with firewalls
- ✅ **Completely optional**: DDS works perfectly without it
- ✅ **Think "phone book"**: Helps find numbers, doesn't handle calls

## Architecture

```
┌─────────────────┐    DDS Messages    ┌─────────────────┐
│  Publisher      │ ───────────────→   │  TUI Subscriber │
│  Thread         │   (Direct P2P)     │  Thread         │
│                 │                    │                 │
│ • Hello World   │                    │ • Lipgloss UI   │
│ • Every 2s      │                    │ • Message List │
│ • DDS Publish   │                    │ • Timestamps    │
└─────────────────┘                    └─────────────────┘
        ↑                                       ↑
        └─── No Broker Required! ───────────────┘
```

## Quick Start

### **First Time Setup**
```bash
# Show all available commands
just --list

# See detailed workflow examples
just examples

# Initialize Go module (if needed)
just init my-dds-app

# Build development environment
just dev-image
```

### **Development Workflows**

#### **Interactive Development**
```bash
# Start development shell with Fast DDS environment
just dev-shell

# Inside the container, your code is mounted at /workspace
go mod tidy
go build -o myapp *.go
./myapp
```

#### **Quick Build-Run Cycle**
```bash
# Build and run in one command
just dev-cycle

# Build specific target
just dev-build myapp

# Run specific binary
just dev-run myapp
```

#### **Multi-Instance Testing**
```bash
# Test DDS discovery automatically
just test-discovery        # 2 instances
just test-discovery 5      # 5 instances
```

#### **Docker Compose Workflow**
```bash
# Long-running development container
just compose-dev

# Build using compose
just compose-build

# Stop services
just compose-down
```

## Building and Running

### **Development (Recommended)**

Uses hermetic Fast DDS environment via Docker:

```bash
# Build development environment (one time)
just dev-image

# Quick development cycle
just dev-cycle                    # Build and run 'cardinal'
just dev-cycle myapp              # Build and run custom app

# Or step by step
just dev-build cardinal           # Build application
just dev-run cardinal             # Run application

# Interactive development
just dev-shell                    # Full development environment
```

### **Legacy Methods**

For systems without `just` installed:

```bash
# Using legacy Makefile (still works)
make dev-build
make dev-run

# Direct Go (mock DDS only)
go run main.go
```

## Usage

1. **Start the application**:
   ```bash
   just dev-run cardinal
   ```

2. **Interact with the TUI**:
   - The application will display a beautiful terminal interface
   - Messages from the publisher thread will appear in real-time
   - Press `q` or `Ctrl+C` to quit

3. **Test multi-instance DDS**:
   ```bash
   just test-discovery 3    # Test with 3 instances
   ```

## Project Structure

```
cardinal/
├── main.go                 # Main application with TUI and mock DDS
├── fastdds_integration.go  # CGO bindings for Fast DDS
├── fastdds.h              # C header for DDS interface
├── fastdds.cpp            # C++ implementation using Fast DDS
├── fastdds_profiles.xml   # Fast DDS configuration
├── justfile               # Modern command runner (⭐ NEW)
├── Makefile               # Legacy build system
├── Dockerfile             # Hermetic Fast DDS development environment
├── docker-compose.dev.yml # Development container configuration
├── go.mod                 # Go module definition
├── README.md              # This file
└── DEVELOPMENT.md         # Detailed development guide
```

## Key Components

### 1. DDS Communication
- **Publisher**: Sends "Hello World" messages with timestamps
- **Subscriber**: Receives messages and forwards to TUI
- **Topics**: Uses "hello_topic" for communication

### 2. TUI Interface (Lipgloss)
- **Title**: Styled header with project name
- **Message List**: Recent DDS messages with timestamps
- **Borders**: Rounded borders with purple accent
- **Colors**: Green messages, gray timestamps

### 3. Threading
- **Publisher Goroutine**: Independent message generation
- **Subscriber Goroutine**: DDS message reception
- **Main Thread**: TUI event loop with Bubble Tea

## Customization

### Styling
Modify the lipgloss styles in `main.go`:
```go
titleStyle := lipgloss.NewStyle().
    Foreground(lipgloss.Color("#FAFAFA")).
    Background(lipgloss.Color("#7D56F4"))
```

### Message Frequency
Change the ticker duration in `helloWorldPublisher`:
```go
ticker := time.NewTicker(2 * time.Second)  // Adjust this
```

### DDS Settings
Modify domain ID and topic name in `main.go`:
```go
// For real DDS
pub, sub := NewRealDDSSystem(0, "your_topic")

// For mock DDS  
pub, sub := NewDDSSystem()
```

## Command Reference

### **Development Commands**
| Command | Description |
|---------|-------------|
| `just dev-image` | Build hermetic Fast DDS environment |
| `just dev-shell` | Start interactive development shell |
| `just dev-build [target]` | Build application in DDS environment |
| `just dev-run [binary]` | Run application in DDS environment |
| `just dev-cycle [target]` | Build and run in one command |
| `just dev-clean` | Clean development resources |

### **Testing Commands**
| Command | Description |
|---------|-------------|
| `just test` | Run tests in Fast DDS environment |
| `just test-discovery [N]` | Test DDS discovery with N instances |
| `just fmt` | Format Go code |
| `just lint` | Lint Go code |

### **Utility Commands**
| Command | Description |
|---------|-------------|
| `just info` | Show environment information |
| `just examples` | Show workflow examples |
| `just init <module>` | Initialize new Go module |

### **Docker Compose Commands**
| Command | Description |
|---------|-------------|
| `just compose-dev` | Start long-running dev container |
| `just compose-build` | One-off build via compose |
| `just compose-down` | Stop compose services |

## Dependencies

- **Go 1.21+**
- **Just**: Modern command runner ([install guide](https://github.com/casey/just#installation))
- **Docker**: Container runtime
- **Lipgloss**: Terminal styling
- **Bubble Tea**: TUI framework
- **Fast DDS** (via Docker): Real-time communication

## Migration from Shell Scripts

If you're coming from the previous version with shell scripts:

| Old Command | New Command |
|-------------|-------------|
| `./scripts/dev-shell.sh` | `just dev-shell` |
| `./scripts/build-in-dds.sh` | `just dev-build` |
| `./scripts/run-in-dds.sh` | `just dev-run` |
| `make dev-build` | `just dev-build` |
| `make dev-run` | `just dev-run` |

The `justfile` provides better syntax, integrated help, and more powerful scripting than the previous shell scripts.

## Troubleshooting

### Build Issues
- Ensure Docker is running: `just info`
- Rebuild environment: `just dev-clean && just dev-image`
- Check Go module: `just init <module-name>` if needed

### Runtime Issues
- Press `q` or `Ctrl+C` to exit cleanly
- Check terminal size (minimum 80 characters wide recommended)
- Verify DDS domain connectivity for real DDS mode

### Just Installation
```bash
# Install just via cargo
cargo install just

# Or via package managers
# macOS: brew install just
# Ubuntu: snap install --edge just
```

## License

This is a demonstration project. Feel free to use and modify as needed. 