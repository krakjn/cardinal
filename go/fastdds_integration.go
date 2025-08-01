package main

/*
#cgo CFLAGS:
#cgo CPPFLAGS: -I/usr/local/include -I/workspace/lib
#cgo CXXFLAGS: -std=c++17
#cgo LDFLAGS: -L/usr/local/lib -L/workspace/build -lcardinal-fastdds -lfastdds -lfastcdr -lstdc++
#include "fastdds.h"

#include <stdlib.h>
*/
import "C"
import (
	"fmt"
	"time"
	"unsafe"
)

// RealDDSPublisher wraps the simplified Fast DDS publisher
type RealDDSPublisher struct {
	publisher C.SimpleDDSPublisher
	topic     string
}

// RealDDSSubscriber wraps the simplified Fast DDS subscriber
type RealDDSSubscriber struct {
	subscriber C.SimpleDDSSubscriber
	topic      string
}

// NewRealDDSSystem creates a real Fast DDS publisher and subscriber
func NewRealDDSSystem(domainID int, topic string) (*RealDDSPublisher, *RealDDSSubscriber, error) {
	// Create publisher
	topicCStr := C.CString(topic)
	defer C.free(unsafe.Pointer(topicCStr))

	publisher := C.create_simple_publisher(topicCStr)
	if publisher == nil {
		return nil, nil, fmt.Errorf("failed to create DDS publisher")
	}

	// Create subscriber
	subscriber := C.create_simple_subscriber(topicCStr)
	if subscriber == nil {
		C.destroy_simple_publisher(publisher)
		return nil, nil, fmt.Errorf("failed to create DDS subscriber")
	}

	pub := &RealDDSPublisher{
		publisher: publisher,
		topic:     topic,
	}

	sub := &RealDDSSubscriber{
		subscriber: subscriber,
		topic:      topic,
	}

	return pub, sub, nil
}

// Publish sends a message via Fast DDS
func (p *RealDDSPublisher) Publish(msg DDSMessage) error {
	contentCStr := C.CString(msg.Content)
	defer C.free(unsafe.Pointer(contentCStr))

	timestamp := C.long(msg.Timestamp.Unix())

	result := C.publish_simple_message(p.publisher, contentCStr, timestamp)
	if result != 0 {
		return fmt.Errorf("failed to publish message")
	}

	return nil
}

// Subscribe receives messages from Fast DDS
func (s *RealDDSSubscriber) Subscribe() <-chan DDSMessage {
	msgChan := make(chan DDSMessage, 100)

	go func() {
		defer close(msgChan)

		for {
			var cMsg C.SimpleMessage
			result := C.receive_simple_message(s.subscriber, &cMsg)

			if result == 0 {
				msg := DDSMessage{
					Content:   C.GoString(&cMsg.message[0]),
					Timestamp: time.Unix(int64(cMsg.timestamp), 0),
				}
				msgChan <- msg
			}

			// Small sleep to prevent busy waiting
			time.Sleep(10 * time.Millisecond)
		}
	}()

	return msgChan
}

// Cleanup cleans up Fast DDS resources
func (p *RealDDSPublisher) Cleanup() {
	if p.publisher != nil {
		C.destroy_simple_publisher(p.publisher)
	}
}

func (s *RealDDSSubscriber) Cleanup() {
	if s.subscriber != nil {
		C.destroy_simple_subscriber(s.subscriber)
	}
}
