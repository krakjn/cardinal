# Cardinal Zig - Fast DDS Integration

A Zig implementation of the Cardinal Fast DDS demo, showcasing C interop with Fast DDS.

## Features

- Real Fast DDS integration via C bindings
- Mock DDS fallback system
- Thread-based publisher/subscriber pattern
- Proper memory management with Zig allocators
- Build caching support

## Building

### Using Docker (Recommended)

```bash
# Build the Zig version
just build-zig

# Run the application
just run-zig

# Clean build artifacts
just clean-zig
```

### Local Build (requires Zig 0.13.0+)

```bash
cd zig/
zig build
```

## Project Structure

```
zig/
├── build.zig              # Build configuration
├── src/
│   ├── main.zig          # Main application entry point
│   └── fastdds.zig       # Fast DDS C bindings and wrapper
└── zig-out/              # Build outputs (ignored by git)
```

## Key Differences from Go Version

- **Memory Management**: Explicit allocator usage instead of garbage collection
- **Error Handling**: Zig's explicit error handling with `try`/`catch`
- **C Interop**: Direct C bindings using `@cImport` and `@cInclude`
- **Concurrency**: Standard library threading instead of goroutines
- **Build System**: `build.zig` instead of `go.mod`

## Architecture

The Zig version maintains the same basic architecture as the Go version:

1. **FastDDS Wrapper**: C++ library compiled to static library
2. **C Bindings**: Header file interface (`fastdds.h`)
3. **Zig Integration**: Direct C interop via `@cImport`
4. **Application Logic**: Publisher/subscriber threads with fallback to mock DDS

## Fast DDS Dependencies

The application links against:
- `libfastdds` (Fast DDS core library)
- `libfastcdr` (Fast CDR serialization)
- C++ standard library

## Performance Notes

- Zero-cost C interop (no marshaling overhead)
- Explicit memory management (no GC pauses)
- Compile-time optimizations
- Static linking for better performance