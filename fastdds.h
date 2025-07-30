#ifndef FASTDDS_SIMPLE_H
#define FASTDDS_SIMPLE_H

#ifdef __cplusplus
extern "C" {
#endif

// Simple message structure
typedef struct {
    char message[256];
    long timestamp;
} SimpleMessage;

// Opaque handles for C interface
typedef void* SimpleDDSPublisher;
typedef void* SimpleDDSSubscriber;

// Publisher functions
SimpleDDSPublisher create_simple_publisher(const char* topic_name);
int publish_simple_message(SimpleDDSPublisher pub, const char* message, long timestamp);
void destroy_simple_publisher(SimpleDDSPublisher pub);

// Subscriber functions
SimpleDDSSubscriber create_simple_subscriber(const char* topic_name);
int receive_simple_message(SimpleDDSSubscriber sub, SimpleMessage* msg);
void destroy_simple_subscriber(SimpleDDSSubscriber sub);

#ifdef __cplusplus
}
#endif

#endif // FASTDDS_SIMPLE_H 