#include "fastdds.h"
#include <fastdds/dds/domain/DomainParticipantFactory.hpp>
#include <fastdds/dds/domain/DomainParticipant.hpp>
#include <fastdds/dds/publisher/Publisher.hpp>
#include <fastdds/dds/publisher/DataWriter.hpp>
#include <fastdds/dds/subscriber/Subscriber.hpp>
#include <fastdds/dds/subscriber/DataReader.hpp>
#include <fastdds/dds/topic/Topic.hpp>
#include <fastdds/dds/topic/TypeSupport.hpp>
#include <fastdds/dds/subscriber/SampleInfo.hpp>
#include <fastdds/rtps/common/SerializedPayload.hpp>
#include <string>
#include <iostream>
#include <memory>
#include <cstring>

using namespace eprosima::fastdds::dds;
using namespace eprosima::fastdds::rtps;

// Simple message class for Fast DDS
class SimpleMessageData {
public:
    std::string message;
    int64_t timestamp;

    SimpleMessageData() = default;
    SimpleMessageData(const std::string& msg, int64_t ts) : message(msg), timestamp(ts) {}
};

// Simplified TypeSupport for Fast DDS
class SimpleMessageTypeSupport : public TopicDataType {
public:
    SimpleMessageTypeSupport() {
        set_name("SimpleMessage");
        max_serialized_type_size = 300; // 256 + some overhead
        is_compute_key_provided = false;
    }

    bool serialize(const void* data, SerializedPayload_t& payload, DataRepresentationId_t representation) override {
        const SimpleMessageData* msg_data = static_cast<const SimpleMessageData*>(data);
        
        // Simple serialization: message length + message + timestamp
        uint32_t msg_len = static_cast<uint32_t>(msg_data->message.length());
        
        payload.reserve(sizeof(uint32_t) + msg_len + sizeof(int64_t));
        payload.pos = 0;
        
        // Serialize message length
        memcpy(payload.data + payload.pos, &msg_len, sizeof(uint32_t));
        payload.pos += sizeof(uint32_t);
        
        // Serialize message
        memcpy(payload.data + payload.pos, msg_data->message.c_str(), msg_len);
        payload.pos += msg_len;
        
        // Serialize timestamp
        memcpy(payload.data + payload.pos, &msg_data->timestamp, sizeof(int64_t));
        payload.pos += sizeof(int64_t);
        
        payload.length = payload.pos;
        return true;
    }

    bool deserialize(SerializedPayload_t& payload, void* data) override {
        SimpleMessageData* msg_data = static_cast<SimpleMessageData*>(data);
        
        payload.pos = 0;
        
        // Deserialize message length
        uint32_t msg_len;
        memcpy(&msg_len, payload.data + payload.pos, sizeof(uint32_t));
        payload.pos += sizeof(uint32_t);
        
        // Deserialize message
        char buffer[256];
        memcpy(buffer, payload.data + payload.pos, std::min(msg_len, 255u));
        buffer[std::min(msg_len, 255u)] = '\0';
        msg_data->message = std::string(buffer);
        payload.pos += msg_len;
        
        // Deserialize timestamp
        memcpy(&msg_data->timestamp, payload.data + payload.pos, sizeof(int64_t));
        payload.pos += sizeof(int64_t);
        
        return true;
    }

    uint32_t calculate_serialized_size(const void* data, DataRepresentationId_t representation) override {
        const SimpleMessageData* msg_data = static_cast<const SimpleMessageData*>(data);
        return sizeof(uint32_t) + msg_data->message.length() + sizeof(int64_t);
    }

    void* create_data() override {
        return new SimpleMessageData();
    }

    void delete_data(void* data) override {
        delete static_cast<SimpleMessageData*>(data);
    }

    bool compute_key(SerializedPayload_t& payload, InstanceHandle_t& handle, bool force_md5) override {
        return true;
    }

    bool compute_key(const void* data, InstanceHandle_t& handle, bool force_md5) override {
        return true;
    }
};

// Publisher wrapper
struct SimplePublisherWrapper {
    DomainParticipant* participant;
    Publisher* publisher;
    Topic* topic;
    DataWriter* writer;
    TypeSupport type_support;
};

// Subscriber wrapper
struct SimpleSubscriberWrapper {
    DomainParticipant* participant;
    Subscriber* subscriber;
    Topic* topic;
    DataReader* reader;
    TypeSupport type_support;
};

extern "C" {

SimpleDDSPublisher create_simple_publisher(const char* topic_name) {
    try {
        // Create participant
        DomainParticipant* participant = DomainParticipantFactory::get_instance()->create_participant(
            0, PARTICIPANT_QOS_DEFAULT);
        if (!participant) {
            std::cerr << "Failed to create participant" << std::endl;
            return nullptr;
        }

        // Create wrapper
        SimplePublisherWrapper* wrapper = new SimplePublisherWrapper();
        wrapper->participant = participant;
        wrapper->type_support = TypeSupport(new SimpleMessageTypeSupport());

        // Register type
        if (wrapper->type_support.register_type(participant) != RETCODE_OK) {
            std::cerr << "Failed to register type" << std::endl;
            delete wrapper;
            return nullptr;
        }

        // Create topic
        wrapper->topic = participant->create_topic(
            topic_name, wrapper->type_support.get_type_name(), TOPIC_QOS_DEFAULT);
        if (!wrapper->topic) {
            std::cerr << "Failed to create topic" << std::endl;
            delete wrapper;
            return nullptr;
        }

        // Create publisher
        wrapper->publisher = participant->create_publisher(PUBLISHER_QOS_DEFAULT);
        if (!wrapper->publisher) {
            std::cerr << "Failed to create publisher" << std::endl;
            delete wrapper;
            return nullptr;
        }

        // Create writer
        wrapper->writer = wrapper->publisher->create_datawriter(wrapper->topic, DATAWRITER_QOS_DEFAULT);
        if (!wrapper->writer) {
            std::cerr << "Failed to create writer" << std::endl;
            delete wrapper;
            return nullptr;
        }

        return wrapper;
    } catch (const std::exception& e) {
        std::cerr << "Exception in create_simple_publisher: " << e.what() << std::endl;
        return nullptr;
    }
}

int publish_simple_message(SimpleDDSPublisher pub, const char* message, long timestamp) {
    SimplePublisherWrapper* wrapper = static_cast<SimplePublisherWrapper*>(pub);
    if (!wrapper || !wrapper->writer) {
        return -1;
    }

    try {
        SimpleMessageData msg_data(std::string(message), timestamp);
        return wrapper->writer->write(&msg_data) == RETCODE_OK ? 0 : -1;
    } catch (const std::exception& e) {
        std::cerr << "Exception in publish_simple_message: " << e.what() << std::endl;
        return -1;
    }
}

void destroy_simple_publisher(SimpleDDSPublisher pub) {
    SimplePublisherWrapper* wrapper = static_cast<SimplePublisherWrapper*>(pub);
    if (wrapper) {
        if (wrapper->writer) wrapper->publisher->delete_datawriter(wrapper->writer);
        if (wrapper->topic) wrapper->participant->delete_topic(wrapper->topic);
        if (wrapper->publisher) wrapper->participant->delete_publisher(wrapper->publisher);
        if (wrapper->participant) DomainParticipantFactory::get_instance()->delete_participant(wrapper->participant);
        delete wrapper;
    }
}

SimpleDDSSubscriber create_simple_subscriber(const char* topic_name) {
    try {
        // Create participant
        DomainParticipant* participant = DomainParticipantFactory::get_instance()->create_participant(
            0, PARTICIPANT_QOS_DEFAULT);
        if (!participant) {
            std::cerr << "Failed to create participant" << std::endl;
            return nullptr;
        }

        // Create wrapper
        SimpleSubscriberWrapper* wrapper = new SimpleSubscriberWrapper();
        wrapper->participant = participant;
        wrapper->type_support = TypeSupport(new SimpleMessageTypeSupport());

        // Register type
        if (wrapper->type_support.register_type(participant) != RETCODE_OK) {
            std::cerr << "Failed to register type" << std::endl;
            delete wrapper;
            return nullptr;
        }

        // Create topic
        wrapper->topic = participant->create_topic(
            topic_name, wrapper->type_support.get_type_name(), TOPIC_QOS_DEFAULT);
        if (!wrapper->topic) {
            std::cerr << "Failed to create topic" << std::endl;
            delete wrapper;
            return nullptr;
        }

        // Create subscriber
        wrapper->subscriber = participant->create_subscriber(SUBSCRIBER_QOS_DEFAULT);
        if (!wrapper->subscriber) {
            std::cerr << "Failed to create subscriber" << std::endl;
            delete wrapper;
            return nullptr;
        }

        // Create reader
        wrapper->reader = wrapper->subscriber->create_datareader(wrapper->topic, DATAREADER_QOS_DEFAULT);
        if (!wrapper->reader) {
            std::cerr << "Failed to create reader" << std::endl;
            delete wrapper;
            return nullptr;
        }

        return wrapper;
    } catch (const std::exception& e) {
        std::cerr << "Exception in create_simple_subscriber: " << e.what() << std::endl;
        return nullptr;
    }
}

int receive_simple_message(SimpleDDSSubscriber sub, SimpleMessage* msg) {
    SimpleSubscriberWrapper* wrapper = static_cast<SimpleSubscriberWrapper*>(sub);
    if (!wrapper || !wrapper->reader) {
        return -1;
    }

    try {
        SampleInfo info;
        SimpleMessageData msg_data;
        
        if (wrapper->reader->read_next_sample(&msg_data, &info) == RETCODE_OK) {
            strncpy(msg->message, msg_data.message.c_str(), 255);
            msg->message[255] = '\0';
            msg->timestamp = msg_data.timestamp;
            return 0;
        }
        return -1; // No data available
    } catch (const std::exception& e) {
        std::cerr << "Exception in receive_simple_message: " << e.what() << std::endl;
        return -1;
    }
}

void destroy_simple_subscriber(SimpleDDSSubscriber sub) {
    SimpleSubscriberWrapper* wrapper = static_cast<SimpleSubscriberWrapper*>(sub);
    if (wrapper) {
        if (wrapper->reader) wrapper->subscriber->delete_datareader(wrapper->reader);
        if (wrapper->topic) wrapper->participant->delete_topic(wrapper->topic);
        if (wrapper->subscriber) wrapper->participant->delete_subscriber(wrapper->subscriber);
        if (wrapper->participant) DomainParticipantFactory::get_instance()->delete_participant(wrapper->participant);
        delete wrapper;
    }
}

}