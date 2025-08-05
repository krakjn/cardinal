# Cardinal - Multi-Language FastDDS TUI Showcase

A beautiful, multi-language demonstration of FastDDS (Fast Data Distribution Service) integration with stunning terminal user interfaces. Features a sophisticated Zig TUI built with libvaxis, showcasing real-time message streaming, progress indicators, and advanced UI components.

## Featured Technologies

- **Zig + libvaxis** - Stunning terminal UI with live DDS message display
- **Rust + ratatui** - High-performance FastDDS bindings and TUI
- **Go + lipgloss** - FastDDS integration with elegant interfaces  
- **FastDDS** - Real-time data distribution service
- **Docker** - Consistent cross-platform development

## Quick Start
| Command | Description |
|---------|-------------|
| `just image` | Build the Docker image |
| `just build [lang]` | Build specific language or all implementations |
| `just run <lang>` | Run the TUI for specified language (zig/rust/go) |
| `just clean` | Clean build artifacts and containers |
| `just shell` | Enter development container |
| `just _lib ` | (in container) Build C++ FastDDS library |
| `just _zig ` | (in container) Build Zig TUI |
| `just _rust` | (in container) Build Rust TUI   |
| `just _go  ` | (in container) Build Go TUI |


## 🛠️ Development

### **Requirements**
- [Docker](https://docs.docker.com/get-docker/)
- [Just](https://github.com/casey/just) (command runner)

## 🎯 Message Flow

1. **Mock Publisher** generates realistic sensor data every second
2. **FastDDS** handles message distribution between processes
3. **TUI Subscriber** receives and displays messages in real-time
4. **Progress Indicators** show processing status and throughput
5. **Analytics Engine** computes real-time metrics and visualizations

### **Sample Messages**
```
📡 Sensor temperature: 23.5°C
📍 GPS coordinates: 40.7128, -74.0060  
✅ System status: All systems operational
🔋 Battery level: 85%
📶 Network connectivity: Strong
💾 Memory usage: 45%
⚡ CPU load: 12%
```
