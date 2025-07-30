# Cardinal - Lipgloss TUI Demo

A beautiful terminal user interface demo built with Go, showcasing:
- **Lipgloss** for stunning TUI styling
- **Bubble Tea** for interactive terminal apps  
- **Mock DDS messaging** between two goroutines
- **Docker** for consistent development environment

## 🚀 Quick Start

```bash
# Build the application
just build

# Run the application  
just run

# Or do both in one command
just dev
```

## 📋 Commands

- `just build` - Build the application
- `just run` - Run the application
- `just dev` - Build and run (development cycle)
- `just shell` - Start development shell
- `just clean` - Clean up Docker resources

## 🎯 What It Does

The application demonstrates a two-threaded architecture:

1. **Publisher Thread**: Sends "Hello World" messages every 2 seconds
2. **TUI Thread**: Displays messages in a beautiful terminal interface using Lipgloss

Messages are passed between threads using a mock DDS (Data Distribution Service) system.

## 🛠️ Development

The entire development environment runs in Docker for consistency across machines.

### Requirements

- [Docker](https://docs.docker.com/get-docker/)
- [Docker Compose](https://docs.docker.com/compose/install/)
- [Just](https://github.com/casey/just) (command runner)

### Project Structure

```
cardinal/
├── main.go              # Main application
├── go.mod               # Go dependencies
├── Dockerfile           # Development environment
├── docker-compose.yml   # Container orchestration
├── justfile             # Command runner
└── README.md            # This file
```

## 🎨 Features

- **Beautiful TUI**: Styled with Lipgloss borders, colors, and layouts
- **Real-time Updates**: Live message display with timestamps
- **Graceful Shutdown**: Clean exit with Ctrl+C or 'q'
- **Containerized**: Consistent development environment

## 🧩 Architecture

```
┌─────────────────┐    Mock DDS    ┌─────────────────┐
│  Publisher      │ ────Channel───▶│ TUI Subscriber  │
│  (Goroutine)    │                │ (Bubble Tea)    │
│                 │                │                 │
│ • Hello World   │                │ • Lipgloss UI   │
│ • Every 2s      │                │ • Live Updates  │
│ • Timestamps    │                │ • Styling       │
└─────────────────┘                └─────────────────┘
```

## 📄 License

MIT License - feel free to use this as a starting point for your own TUI applications!