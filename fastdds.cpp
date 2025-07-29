#include "fastdds.h"
#include <fastdds/dds/domain/DomainParticipantFactory.hpp>
#include <fastdds/dds/domain/DomainParticipant.hpp>
#include <fastdds/dds/topic/TypeSupport.hpp>
#include <fastdds/dds/publisher/Publisher.hpp>
#include <fastdds/dds/publisher/DataWriter.hpp>
#include <fastdds/dds/subscriber/Subscriber.hpp>
#include <fastdds/dds/subscriber/DataReader.hpp>
#include <fastdds/dds/subscriber/SampleInfo.hpp>
#include <cstring>
#include <chrono>

using namespace eprosima::fastdds::dds;

// HelloWorld message type for Fast DDS
class HelloWorldMsgType
{
public:
    std::string content;
    int64_t timestamp;
    
    HelloWorldMsgType() = default;
    HelloWorldMsgType(const std::string& content, int64_t timestamp)
        : content(content), timestamp(timestamp) {}
};

// TypeSupport implementation (simplified)
class HelloWorldMsgTypeSupport : public TopicDataType
{
public:
    HelloWorldMsgTypeSupport() 
    {
        setName("HelloWorldMsg");
        m_typeSize = 264; // 256 + 8 bytes
    }

    bool serialize(void* data, SerializedPayload_t* payload) override
    {
        HelloWorldMsgType* msg = static_cast<HelloWorldMsgType*>(data);
        // Simplified serialization - in real implementation you'd use proper serialization
        memcpy(payload->data, msg->content.c_str(), std::min(msg->content.size(), size_t(255)));
        payload->data[255] = '\0';
        memcpy(payload->data + 256, &msg->timestamp, sizeof(int64_t));
        payload->length = 264;
        return true;
    }

    bool deserialize(SerializedPayload_t* payload, void* data) override
    {
        HelloWorldMsgType* msg = static_cast<HelloWorldMsgType*>(data);
        char content[256];
        memcpy(content, payload->data, 256);
        content[255] = '\0';
        msg->content = std::string(content);
        memcpy(&msg->timestamp, payload->data + 256, sizeof(int64_t));
        return true;
    }

    std::function<uint32_t()> getSerializedSizeProvider(void* data) override
    {
        return []() -> uint32_t { return 264; };
    }

    void* createData() override
    {
        return new HelloWorldMsgType();
    }

    void deleteData(void* data) override
    {
        delete static_cast<HelloWorldMsgType*>(data);
    }

    bool getKey(void* data, InstanceHandle_t* handle, bool force_md5) override
    {
        return true;
    }
};

// Wrapper structures
struct DDSPublisherWrapper {
    DomainParticipant* participant;
    Publisher* publisher;
    Topic* topic;
    DataWriter* writer;
    TypeSupport type_support;
};

struct DDSSubscriberWrapper {
    DomainParticipant* participant;
    Subscriber* subscriber;
    Topic* topic;
    DataReader* reader;
    TypeSupport type_support;
};

extern "C" {

DDSDomainParticipant_t* create_participant(int domain_id) {
    DomainParticipantQos pqos;
    pqos.name("Cardinal_Participant");
    
    DomainParticipant* participant = DomainParticipantFactory::get_instance()->create_participant(
        domain_id, pqos);
    
    return static_cast<DDSDomainParticipant_t*>(participant);
}

DDSPublisher_t* create_publisher(DDSDomainParticipant_t* participant_ptr, const char* topic_name) {
    DomainParticipant* participant = static_cast<DomainParticipant*>(participant_ptr);
    
    DDSPublisherWrapper* wrapper = new DDSPublisherWrapper();
    wrapper->participant = participant;
    wrapper->type_support = TypeSupport(new HelloWorldMsgTypeSupport());
    
    // Register type
    wrapper->type_support.register_type(participant);
    
    // Create topic
    wrapper->topic = participant->create_topic(topic_name, "HelloWorldMsg", TOPIC_QOS_DEFAULT);
    
    // Create publisher
    wrapper->publisher = participant->create_publisher(PUBLISHER_QOS_DEFAULT);
    
    // Create writer
    wrapper->writer = wrapper->publisher->create_datawriter(wrapper->topic, DATAWRITER_QOS_DEFAULT);
    
    return static_cast<DDSPublisher_t*>(wrapper);
}

int publish_message(DDSPublisher_t* publisher_ptr, const char* content, long timestamp) {
    DDSPublisherWrapper* wrapper = static_cast<DDSPublisherWrapper*>(publisher_ptr);
    
    HelloWorldMsgType msg(std::string(content), timestamp);
    return wrapper->writer->write(&msg) == ReturnCode_t::RETCODE_OK ? 0 : -1;
}

DDSSubscriber_t* create_subscriber(DDSDomainParticipant_t* participant_ptr, const char* topic_name) {
    DomainParticipant* participant = static_cast<DomainParticipant*>(participant_ptr);
    
    DDSSubscriberWrapper* wrapper = new DDSSubscriberWrapper();
    wrapper->participant = participant;
    wrapper->type_support = TypeSupport(new HelloWorldMsgTypeSupport());
    
    // Register type
    wrapper->type_support.register_type(participant);
    
    // Create topic
    wrapper->topic = participant->create_topic(topic_name, "HelloWorldMsg", TOPIC_QOS_DEFAULT);
    
    // Create subscriber
    wrapper->subscriber = participant->create_subscriber(SUBSCRIBER_QOS_DEFAULT);
    
    // Create reader
    wrapper->reader = wrapper->subscriber->create_datareader(wrapper->topic, DATAREADER_QOS_DEFAULT);
    
    return static_cast<DDSSubscriber_t*>(wrapper);
}

int receive_message(DDSSubscriber_t* subscriber_ptr, HelloWorldMsg* msg, int timeout_ms) {
    DDSSubscriberWrapper* wrapper = static_cast<DDSSubscriberWrapper*>(subscriber_ptr);
    
    SampleInfo info;
    HelloWorldMsgType dds_msg;
    
    if (wrapper->reader->read_next_sample(&dds_msg, &info) == ReturnCode_t::RETCODE_OK) {
        strncpy(msg->content, dds_msg.content.c_str(), 255);
        msg->content[255] = '\0';
        msg->timestamp = dds_msg.timestamp;
        return 0;
    }
    
    return -1; // No data available
}

void destroy_publisher(DDSPublisher_t* publisher_ptr) {
    DDSPublisherWrapper* wrapper = static_cast<DDSPublisherWrapper*>(publisher_ptr);
    if (wrapper) {
        if (wrapper->writer) wrapper->publisher->delete_datawriter(wrapper->writer);
        if (wrapper->topic) wrapper->participant->delete_topic(wrapper->topic);
        if (wrapper->publisher) wrapper->participant->delete_publisher(wrapper->publisher);
        delete wrapper;
    }
}

void destroy_subscriber(DDSSubscriber_t* subscriber_ptr) {
    DDSSubscriberWrapper* wrapper = static_cast<DDSSubscriberWrapper*>(subscriber_ptr);
    if (wrapper) {
        if (wrapper->reader) wrapper->subscriber->delete_datareader(wrapper->reader);
        if (wrapper->topic) wrapper->participant->delete_topic(wrapper->topic);
        if (wrapper->subscriber) wrapper->participant->delete_subscriber(wrapper->subscriber);
        delete wrapper;
    }
}

void destroy_participant(DDSDomainParticipant_t* participant_ptr) {
    DomainParticipant* participant = static_cast<DomainParticipant*>(participant_ptr);
    if (participant) {
        DomainParticipantFactory::get_instance()->delete_participant(participant);
    }
}

} 