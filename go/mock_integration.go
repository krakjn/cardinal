//go:build !fastdds
// +build !fastdds

package main

import "fmt"

// Mock implementation when FastDDS is not available
type MockRealDDSPublisher struct {
	*MockDDSPublisher
}

type MockRealDDSSubscriber struct {
	*MockDDSSubscriber
}

func (p *MockRealDDSPublisher) Cleanup() {
	// Nothing to cleanup in mock
}

func (s *MockRealDDSSubscriber) Cleanup() {
	// Nothing to cleanup in mock
}

// NewRealDDSSystem creates a mock DDS system when FastDDS is not available
func NewRealDDSSystem(domainID int, topic string) (*MockRealDDSPublisher, *MockRealDDSSubscriber, error) {
	// Always return an error to force fallback to mock DDS
	return nil, nil, fmt.Errorf("FastDDS not available - using mock DDS")
}
