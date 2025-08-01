# Cardinal Rust - Fast DDS Integration with Ratatui

A Rust implementation of the Cardinal Fast DDS demo, showcasing FFI integration with Fast DDS and a beautiful terminal UI built with ratatui.

## Features

- **Real Fast DDS integration** via FFI bindings to C wrapper
- **Beautiful TUI** with ratatui - real-time message display with colors and styling
- **Mock DDS fallback** system for development without Fast DDS
- **Async architecture** using Tokio for concurrent publisher/subscriber tasks
- **Memory safety** with Rust's ownership system
- **Build caching** support

## Building

### Using Docker (Recommended)

```bash
# Build the Rust version
just build-rust

# Run the application
just run-rust

# Clean build artifacts
just clean-rust
```

### Local Build (requires Rust 1.70+)

```bash
cd rust/
cargo build --release
cargo run
```

## Project Structure

```
rust/
├── Cargo.toml            # Rust dependencies and configuration
├── build.rs              # Build script for FFI compilation
├── src/
│   ├── main.rs          # Main application entry point and async runtime
│   ├── fastdds.rs       # FFI bindings to FastDDS C wrapper
│   └── tui.rs           # Ratatui terminal UI implementation
└── target/              # Build outputs (ignored by git)
```

## Key Features vs Other Versions

### **Rust Advantages:**
- **Memory Safety**: Zero-cost abstractions with compile-time safety guarantees
- **Performance**: Zero-overhead FFI and minimal runtime overhead
- **Beautiful TUI**: Rich terminal interface with ratatui (vs simple prints in Zig)
- **Async/Await**: Modern async runtime with Tokio
- **Error Handling**: Comprehensive error handling with `Result<T, E>`

### **Architecture Comparison:**
- **Go Version**: CGO + Bubble Tea TUI + Goroutines
- **Zig Version**: Direct C interop + Simple terminal output + Threads  
- **Rust Version**: FFI + Ratatui TUI + Async/await tasks

## Fast DDS Integration

The Rust version uses the same shared C++ wrapper as other language versions:

1. **FastDDS Wrapper**: `lib/fastdds.cpp` compiled via build.rs
2. **C Interface**: `lib/fastdds.h` with extern "C" bindings
3. **Rust FFI**: Direct unsafe bindings in `fastdds.rs`
4. **Safe Wrapper**: Memory-safe Rust API with RAII cleanup

## Dependencies

- **ratatui**: Modern terminal UI framework
- **crossterm**: Cross-platform terminal manipulation
- **tokio**: Async runtime for concurrent tasks
- **anyhow**: Error handling
- **chrono**: Date/time handling
- **tracing**: Structured logging

## Fast DDS Libraries

Links against:
- `libfastdds` (Fast DDS core library)
- `libfastcdr` (Fast CDR serialization)
- C++ standard library

## Performance Notes

- **Zero-cost FFI**: Direct C bindings with no marshaling overhead
- **Memory safety**: Rust ownership prevents common C interop bugs
- **Async efficiency**: Tokio's cooperative multitasking
- **UI responsiveness**: Non-blocking terminal updates at 60fps
- **Resource cleanup**: Automatic RAII-based resource management

## Terminal UI Features

- **Real-time message display** with timestamps
- **Color-coded status indicators** (🟢 Active, 🟡 Idle)
- **Scrolling message history** (last 20 messages)
- **Responsive layout** with bordered sections
- **Keyboard controls** (q/Ctrl+C to quit)
- **Unicode support** with emoji indicators