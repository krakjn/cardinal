#ifndef FASTDDS_H
#define FASTDDS_H

#ifdef __cplusplus
extern "C" {
#endif

// Simple C interface for Fast DDS
typedef struct {
    char content[256];
    long timestamp;
} HelloWorldMsg;

typedef void* DDSPublisher_t;
typedef void* DDSSubscriber_t;
typedef void* DDSDomainParticipant_t;

// Publisher functions
DDSDomainParticipant_t* create_participant(int domain_id);
DDSPublisher_t* create_publisher(DDSDomainParticipant_t* participant, const char* topic_name);
int publish_message(DDSPublisher_t* publisher, const char* content, long timestamp);
void destroy_publisher(DDSPublisher_t* publisher);

// Subscriber functions  
DDSSubscriber_t* create_subscriber(DDSDomainParticipant_t* participant, const char* topic_name);
int receive_message(DDSSubscriber_t* subscriber, HelloWorldMsg* msg, int timeout_ms);
void destroy_subscriber(DDSSubscriber_t* subscriber);

// Cleanup
void destroy_participant(DDSDomainParticipant_t* participant);

#ifdef __cplusplus
}
#endif

#endif // FASTDDS_H 