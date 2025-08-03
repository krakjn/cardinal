const std = @import("std");
const vaxis = @import("vaxis");
const print = std.debug.print;

// Simple message structure for demo
const Message = struct {
    content: []const u8,
    timestamp: i64,

    pub fn init(content: []const u8, timestamp: i64) Message {
        return .{
            .content = content,
            .timestamp = timestamp,
        };
    }
};

// Application state
const AppState = struct {
    messages: std.ArrayList(Message),
    publisher_counter: u32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) AppState {
        return .{
            .messages = std.ArrayList(DDSMessage).init(allocator),
            .publisher_counter = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *AppState) void {
        self.messages.deinit();
    }

    pub fn addMessage(self: *AppState, msg: Message) !void {
        try self.messages.append(msg);
        // Keep only last 100 messages to prevent memory issues
        if (self.messages.items.len > 100) {
            _ = self.messages.orderedRemove(0);
        }
    }

    pub fn incrementCounter(self: *AppState) void {
        self.publisher_counter += 1;
    }
};

// Main application widget
const CardinalApp = struct {
    state: *AppState,

    pub fn init(state: *AppState) CardinalApp {
        return .{ .state = state };
    }

    pub fn widget(self: CardinalApp) vaxis.vxfw.Widget {
        const header = self.createHeader();
        const message_list = self.createMessageList();
        const status_bar = self.createStatusBar();

        const flex_column = vaxis.vxfw.FlexColumn{
            .children = &.{
                .{ .widget = header, .flex = 0 },
                .{ .widget = message_list, .flex = 1 },
                .{ .widget = status_bar, .flex = 0 },
            },
        };
        return flex_column.widget();
    }

    fn createHeader(self: CardinalApp) vaxis.vxfw.Widget {
        const title = "🚀 Cardinal - Fast DDS Demo";
        const subtitle = std.fmt.allocPrint(self.state.allocator, "Press Ctrl+C to exit | Messages: {d}", .{self.state.messages.items.len}) catch "Status error";
        defer self.state.allocator.free(subtitle);

        const title_text = vaxis.vxfw.Text{
            .text = title,
            .style = .{
                .fg = .{ .rgb = .{ 255, 255, 255 } },
                .bold = true,
            },
        };

        const subtitle_text = vaxis.vxfw.Text{
            .text = subtitle,
            .style = .{
                .fg = .{ .rgb = .{ 200, 200, 200 } },
            },
        };

        const flex_column = vaxis.vxfw.FlexColumn{
            .children = &.{
                .{ .widget = title_text.widget(), .flex = 0 },
                .{ .widget = subtitle_text.widget(), .flex = 0 },
            },
        };
        return flex_column.widget();
    }

    fn createMessageList(self: CardinalApp) vaxis.vxfw.Widget {
        var children = std.ArrayList(vaxis.vxfw.FlexItem).init(self.state.allocator);
        defer children.deinit();

        // Add messages in reverse order (newest first)
        var i: usize = self.state.messages.items.len;
        while (i > 0) : (i -= 1) {
            const msg = self.state.messages.items[i - 1];
            const timestamp = std.fmt.allocPrint(self.state.allocator, "{d}", .{msg.timestamp}) catch "unknown";
            defer self.state.allocator.free(timestamp);

            const message_text = std.fmt.allocPrint(self.state.allocator, "🔔 [{s}] {s}", .{ timestamp, msg.content }) catch "Error formatting message";
            defer self.state.allocator.free(message_text);

            const text_widget = vaxis.vxfw.Text{
                .text = message_text,
                .style = .{
                    .fg = .{ .rgb = .{ 150, 255, 150 } },
                },
            };

            children.append(.{ .widget = text_widget.widget(), .flex = 0 }) catch continue;
        }

        const flex_column = vaxis.vxfw.FlexColumn{
            .children = children.toOwnedSlice() catch &.{},
        };
        return flex_column.widget();
    }

    fn createStatusBar(self: CardinalApp) vaxis.vxfw.Widget {
        const status_text = std.fmt.allocPrint(self.state.allocator, "📊 Published: {d} | Received: {d}", .{ self.state.publisher_counter, self.state.messages.items.len }) catch "Status error";
        defer self.state.allocator.free(status_text);

        const text_widget = vaxis.vxfw.Text{
            .text = status_text,
            .style = .{
                .fg = .{ .rgb = .{ 255, 255, 0 } },
                .bold = true,
            },
        };
        return text_widget.widget();
    }
};

fn publisherThread(allocator: std.mem.Allocator, state: *AppState) !void {
    while (true) {
        state.incrementCounter();
        const content = try std.fmt.allocPrint(allocator, "Hello World #{d}", .{state.publisher_counter});
        defer allocator.free(content);

        const msg = Message.init(content, std.time.timestamp());
        state.addMessage(msg) catch continue;

        std.time.sleep(2 * std.time.ns_per_s); // 2 seconds
    }
}

fn runDemoMode(allocator: std.mem.Allocator, state: *AppState) !void {
    // Create a simple demo thread that generates messages
    const demo_thread = try std.Thread.spawn(.{}, publisherThread, .{ allocator, state });
    demo_thread.join();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize application state
    const state = try allocator.create(AppState);
    defer {
        state.deinit();
        allocator.destroy(state);
    }
    state.* = AppState.init(allocator);

    // Initialize vaxis app
    var app = try vaxis.vxfw.App.init(allocator);
    defer app.deinit();

    // Create the main widget
    const cardinal_app = CardinalApp.init(state);

    // Start demo in background
    const demo_thread = try std.Thread.spawn(.{}, runDemoMode, .{ allocator, state });

    // Run the TUI
    try app.run(cardinal_app.widget(), .{});

    // Cleanup
    demo_thread.join();
}
