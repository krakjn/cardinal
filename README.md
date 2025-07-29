# Cardinal - Go + Fast DDS + Lipgloss TUI Demo

A demonstration application that combines:
- **Go programming language**
- **Fast DDS** for real-time communication
- **Lipgloss** for beautiful terminal UI styling
- **Bubble Tea** for TUI framework
- **Multi-threading** with goroutines

## Features

- Two concurrent threads:
  1. **Publisher Thread**: Prints "Hello World" messages every 2 seconds
  2. **TUI Thread**: Displays received DDS messages in a beautiful terminal interface
- DDS communication between threads
- Graceful shutdown handling
- Beautiful styling with Lipgloss

## Architecture

```
┌─────────────────┐    DDS Messages    ┌─────────────────┐
│  Publisher      │ ───────────────→   │  TUI Subscriber │
│  Thread         │                    │  Thread         │
│                 │                    │                 │
│ • Hello World   │                    │ • Lipgloss UI   │
│ • Every 2s      │                    │ • Message List │
│ • DDS Publish   │                    │ • Timestamps    │
└─────────────────┘                    └─────────────────┘
```

## Building and Running

### Quick Start (Mock DDS)

The application includes a mock DDS implementation for easy testing without installing Fast DDS:

```bash
# Install dependencies
make deps

# Build and run with mock DDS
make build
make run

# Or directly:
go run main.go
```

### With Real Fast DDS

To use actual Fast DDS, you need to install it first:

```bash
# Install Fast DDS dependencies (Ubuntu/Debian)
make install-fastdds

# Then manually install Fast DDS from:
# https://github.com/eProsima/Fast-DDS

# Build with real Fast DDS
make build-real
make run-real
```

## Usage

1. **Start the application**:
   ```bash
   ./cardinal
   ```

2. **Interact with the TUI**:
   - The application will display a beautiful terminal interface
   - Messages from the publisher thread will appear in real-time
   - Press `q` or `Ctrl+C` to quit

3. **Watch the logs**:
   - The publisher thread logs to stdout
   - Check console output for debugging information

## Project Structure

```
cardinal/
├── main.go                 # Main application with TUI and mock DDS
├── fastdds_integration.go  # CGO bindings for Fast DDS
├── fastdds.h              # C header for DDS interface
├── fastdds.cpp            # C++ implementation using Fast DDS
├── Makefile               # Build system
├── go.mod                 # Go module definition
└── README.md              # This file
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

## Dependencies

- **Go 1.21+**
- **Lipgloss**: Terminal styling
- **Bubble Tea**: TUI framework
- **Fast DDS** (optional): Real-time communication

## Troubleshooting

### Build Issues
- Ensure Go 1.21+ is installed
- Run `go mod tidy` to fix dependencies
- For Fast DDS builds, check CGO settings

### Runtime Issues
- Press `q` or `Ctrl+C` to exit cleanly
- Check terminal size (minimum 80 characters wide recommended)
- Verify DDS domain connectivity for real DDS mode

## License

This is a demonstration project. Feel free to use and modify as needed. 