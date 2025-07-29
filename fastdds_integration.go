package main

/*
#cgo CPPFLAGS: -I.
#cgo LDFLAGS: -L. -lfastrtps -lfastcdr -lstdc++
#include "fastdds.h"
*/
import "C"
import (
	"fmt"
	"time"
	"unsafe"
)

// RealDDSPublisher wraps the C++ Fast DDS publisher
type RealDDSPublisher struct {
	participant C.DDSDomainParticipant_t
	publisher   C.DDSPublisher_t
	topic       string
}

// RealDDSSubscriber wraps the C++ Fast DDS subscriber
type RealDDSSubscriber struct {
	participant C.DDSDomainParticipant_t
	subscriber  C.DDSSubscriber_t
	topic       string
}

// NewRealDDSSystem creates a real Fast DDS publisher and subscriber
func NewRealDDSSystem(domainID int, topic string) (*RealDDSPublisher, *RealDDSSubscriber, error) {
	// Create participant
	participant := C.create_participant(C.int(domainID))
	if participant == nil {
		return nil, nil, fmt.Errorf("failed to create DDS participant")
	}

	// Create publisher
	topicCStr := C.CString(topic)
	defer C.free(unsafe.Pointer(topicCStr))
	
	publisher := C.create_publisher(participant, topicCStr)
	if publisher == nil {
		C.destroy_participant(participant)
		return nil, nil, fmt.Errorf("failed to create DDS publisher")
	}

	// Create subscriber
	subscriber := C.create_subscriber(participant, topicCStr)
	if subscriber == nil {
		C.destroy_publisher(publisher)
		C.destroy_participant(participant)
		return nil, nil, fmt.Errorf("failed to create DDS subscriber")
	}

	pub := &RealDDSPublisher{
		participant: participant,
		publisher:   publisher,
		topic:       topic,
	}

	sub := &RealDDSSubscriber{
		participant: participant,
		subscriber:  subscriber,
		topic:       topic,
	}

	return pub, sub, nil
}

// Publish sends a message via Fast DDS
func (p *RealDDSPublisher) Publish(msg DDSMessage) error {
	contentCStr := C.CString(msg.Content)
	defer C.free(unsafe.Pointer(contentCStr))
	
	timestamp := C.long(msg.Timestamp.Unix())
	
	result := C.publish_message(p.publisher, contentCStr, timestamp)
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
			var cMsg C.HelloWorldMsg
			result := C.receive_message(s.subscriber, &cMsg, C.int(100)) // 100ms timeout
			
			if result == 0 {
				msg := DDSMessage{
					Content:   C.GoString(&cMsg.content[0]),
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
		C.destroy_publisher(p.publisher)
	}
}

func (s *RealDDSSubscriber) Cleanup() {
	if s.subscriber != nil {
		C.destroy_subscriber(s.subscriber)
	}
}

func CleanupParticipant(participant C.DDSDomainParticipant_t) {
	if participant != nil {
		C.destroy_participant(participant)
	}
} 