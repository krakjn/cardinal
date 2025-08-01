const std = @import("std");
const c = @cImport({
    @cInclude("fastdds.h");
});

pub const DDSMessage = struct {
    content: []const u8,
    timestamp: i64,

    pub fn init(content: []const u8, timestamp: i64) DDSMessage {
        return DDSMessage{
            .content = content,
            .timestamp = timestamp,
        };
    }
};

pub const DDSPublisher = struct {
    publisher: c.SimpleDDSPublisher,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, topic: []const u8) !DDSPublisher {
        const topic_cstr = try allocator.dupeZ(u8, topic);
        defer allocator.free(topic_cstr);

        const publisher = c.create_simple_publisher(topic_cstr.ptr);
        if (publisher == null) {
            return error.CreatePublisherFailed;
        }

        return DDSPublisher{
            .publisher = publisher,
            .allocator = allocator,
        };
    }

    pub fn publish(self: *DDSPublisher, msg: DDSMessage) !void {
        const content_cstr = try self.allocator.dupeZ(u8, msg.content);
        defer self.allocator.free(content_cstr);

        const result = c.publish_simple_message(self.publisher, content_cstr.ptr, @intCast(msg.timestamp));
        if (result != 0) {
            return error.PublishFailed;
        }
    }

    pub fn deinit(self: *DDSPublisher) void {
        if (self.publisher != null) {
            c.destroy_simple_publisher(self.publisher);
        }
    }
};

pub const DDSSubscriber = struct {
    subscriber: c.SimpleDDSSubscriber,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, topic: []const u8) !DDSSubscriber {
        const topic_cstr = try allocator.dupeZ(u8, topic);
        defer allocator.free(topic_cstr);

        const subscriber = c.create_simple_subscriber(topic_cstr.ptr);
        if (subscriber == null) {
            return error.CreateSubscriberFailed;
        }

        return DDSSubscriber{
            .subscriber = subscriber,
            .allocator = allocator,
        };
    }

    pub fn receive(self: *DDSSubscriber) ?DDSMessage {
        var c_msg: c.SimpleMessage = undefined;
        const result = c.receive_simple_message(self.subscriber, &c_msg);

        if (result == 0) {
            const len = std.mem.len(@as([*:0]const u8, @ptrCast(&c_msg.message[0])));
            const content = self.allocator.dupe(u8, c_msg.message[0..len]) catch return null;

            return DDSMessage{
                .content = content,
                .timestamp = c_msg.timestamp,
            };
        }

        return null;
    }

    pub fn deinit(self: *DDSSubscriber) void {
        if (self.subscriber != null) {
            c.destroy_simple_subscriber(self.subscriber);
        }
    }
};

// Mock DDS for fallback
pub const MockDDSSystem = struct {
    messages: std.ArrayList(DDSMessage),
    allocator: std.mem.Allocator,
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator) MockDDSSystem {
        return MockDDSSystem{
            .messages = std.ArrayList(DDSMessage).init(allocator),
            .allocator = allocator,
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn createPublisher(self: *MockDDSSystem) MockPublisher {
        return MockPublisher{ .system = self };
    }

    pub fn createSubscriber(self: *MockDDSSystem) MockSubscriber {
        return MockSubscriber{ .system = self };
    }

    pub fn deinit(self: *MockDDSSystem) void {
        for (self.messages.items) |msg| {
            self.allocator.free(msg.content);
        }
        self.messages.deinit();
    }
};

pub const MockPublisher = struct {
    system: *MockDDSSystem,

    pub fn publish(self: *MockPublisher, msg: DDSMessage) !void {
        self.system.mutex.lock();
        defer self.system.mutex.unlock();

        const content_copy = try self.system.allocator.dupe(u8, msg.content);
        try self.system.messages.append(DDSMessage{
            .content = content_copy,
            .timestamp = msg.timestamp,
        });
    }
};

pub const MockSubscriber = struct {
    system: *MockDDSSystem,
    last_index: usize = 0,

    pub fn receive(self: *MockSubscriber) ?DDSMessage {
        self.system.mutex.lock();
        defer self.system.mutex.unlock();

        if (self.last_index < self.system.messages.items.len) {
            const msg = self.system.messages.items[self.last_index];
            self.last_index += 1;
            return msg;
        }
        return null;
    }
};
