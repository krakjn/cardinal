const std = @import("std");
const fastdds = @import("fastdds.zig");
const print = std.debug.print;

const DDSMessage = fastdds.DDSMessage;

// Simple TUI-like output (without external dependencies for now)
fn displayMessage(msg: DDSMessage) void {
    const timestamp = std.time.timestamp();
    const time_str = std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{timestamp}) catch "unknown";
    defer std.heap.page_allocator.free(time_str);

    print("🔔 [{}] {s}\n", .{ msg.timestamp, msg.content });
}

fn publisherThread(allocator: std.mem.Allocator, publisher: anytype) !void {
    var counter: u32 = 0;

    while (true) {
        counter += 1;
        const content = try std.fmt.allocPrint(allocator, "Hello World #{d}", .{counter});
        defer allocator.free(content);

        const msg = DDSMessage.init(content, std.time.timestamp());

        publisher.publish(msg) catch |err| {
            print("❌ Error publishing: {}\n", .{err});
            continue;
        };

        print("📤 Published: {s}\n", .{content});
        std.time.sleep(2 * std.time.ns_per_s); // 2 seconds
    }
}

fn subscriberThread(subscriber: anytype) void {
    while (true) {
        if (subscriber.receive()) |msg| {
            displayMessage(msg);
        }
        std.time.sleep(10 * std.time.ns_per_ms); // 10ms
    }
}

fn runWithRealDDS(allocator: std.mem.Allocator) !void {
    var publisher = fastdds.DDSPublisher.init(allocator, "hello_topic") catch {
        return error.DDSInitFailed;
    };
    defer publisher.deinit();

    var subscriber = fastdds.DDSSubscriber.init(allocator, "hello_topic") catch {
        publisher.deinit();
        return error.DDSInitFailed;
    };
    defer subscriber.deinit();

    print("✅ Using real Fast DDS!\n", .{});

    // Create threads
    const pub_thread = try std.Thread.spawn(.{}, publisherThread, .{ allocator, &publisher });
    const sub_thread = try std.Thread.spawn(.{}, subscriberThread, .{&subscriber});

    // Wait for threads (they run indefinitely)
    pub_thread.join();
    sub_thread.join();
}

fn runWithMockDDS(allocator: std.mem.Allocator) !void {
    var mock_system = fastdds.MockDDSSystem.init(allocator);
    defer mock_system.deinit();

    var publisher = mock_system.createPublisher();
    var subscriber = mock_system.createSubscriber();

    print("⚠️  Using mock DDS (Fast DDS failed)\n", .{});

    // Create threads
    const pub_thread = try std.Thread.spawn(.{}, publisherThread, .{ allocator, &publisher });
    const sub_thread = try std.Thread.spawn(.{}, subscriberThread, .{&subscriber});

    // Wait for threads (they run indefinitely)
    pub_thread.join();
    sub_thread.join();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("🚀 Starting Cardinal Zig - Fast DDS Demo\n", .{});

    // Try real Fast DDS first, fallback to mock
    runWithRealDDS(allocator) catch |err| {
        print("⚠️  Real DDS failed: {}, using mock DDS\n", .{err});
        try runWithMockDDS(allocator);
    };
}
