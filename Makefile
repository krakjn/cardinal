# Makefile for Cardinal Go + Fast DDS application

# Variables
APP_NAME := cardinal
GO_FILES := main.go fastdds_integration.go
CPP_FILES := fastdds.cpp
HEADERS := fastdds.h

# Default Fast DDS installation paths (adjust as needed)
FASTDDS_PREFIX := /usr/local
FASTDDS_INCLUDE := $(FASTDDS_PREFIX)/include
FASTDDS_LIB := $(FASTDDS_PREFIX)/lib

# Compiler flags
CPPFLAGS := -I$(FASTDDS_INCLUDE) -std=c++14 -fPIC
LDFLAGS := -L$(FASTDDS_LIB) -lfastrtps -lfastcdr

# Build targets
.PHONY: all clean deps build run test mock

all: build

# Install Go dependencies
deps:
	go mod download
	go mod tidy

# Build the application (mock DDS version - no Fast DDS required)
build-mock:
	@echo "Building with mock DDS implementation..."
	go build -tags mock -o $(APP_NAME) main.go

# Build with real Fast DDS (requires Fast DDS installation)
build-real: $(CPP_FILES) $(HEADERS)
	@echo "Building C++ wrapper..."
	g++ $(CPPFLAGS) -c fastdds.cpp -o fastdds.o
	ar rcs libfastdds_wrapper.a fastdds.o
	@echo "Building Go application with Fast DDS..."
	CGO_ENABLED=1 go build -o $(APP_NAME) $(GO_FILES)

# Default build uses mock implementation for easier setup
build: build-mock

# Run the application
run: build
	./$(APP_NAME)

# Run with real Fast DDS
run-real: build-real
	./$(APP_NAME)

# Test the application
test:
	go test -v ./...

# Clean build artifacts
clean:
	rm -f $(APP_NAME)
	rm -f *.o
	rm -f *.a
	go clean

# Install Fast DDS (Ubuntu/Debian)
install-fastdds:
	@echo "Installing Fast DDS dependencies..."
	sudo apt update
	sudo apt install -y cmake g++ python3-pip wget git
	sudo apt install -y libasio-dev libtinyxml2-dev
	@echo "Please install Fast DDS manually from: https://github.com/eProsima/Fast-DDS"
	@echo "Or use the provided install script."

# Help
help:
	@echo "Available targets:"
	@echo "  deps         - Install Go dependencies"
	@echo "  build        - Build with mock DDS (default)"
	@echo "  build-real   - Build with real Fast DDS"
	@echo "  run          - Run the application (mock DDS)"
	@echo "  run-real     - Run with real Fast DDS"
	@echo "  test         - Run tests"
	@echo "  clean        - Clean build artifacts"
	@echo "  install-fastdds - Install Fast DDS dependencies"
	@echo "  help         - Show this help" 