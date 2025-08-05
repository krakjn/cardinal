const std = @import("std");
const fmt = std.fmt;
const heap = std.heap;
const mem = std.mem;
const vaxis = @import("vaxis");
const fastdds = @import("fastdds.zig");

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

// DDS Message Display Structure
const DDSMessageDisplay = struct {
    id: u32,
    content: []const u8,
    timestamp: i64,
    formatted_time: []const u8,
    status: []const u8,

    pub fn fromDDSMessage(alloc: std.mem.Allocator, msg: fastdds.DDSMessage, id: u32) !DDSMessageDisplay {
        const formatted_time = try fmt.allocPrint(alloc, "{d}", .{@mod(msg.timestamp, 86400)}); // Show time of day
        const status = if (id % 3 == 0) "✓ Processed" else if (id % 3 == 1) "⏳ Processing" else "📥 Received";

        return DDSMessageDisplay{
            .id = id,
            .content = try alloc.dupe(u8, msg.content),
            .timestamp = msg.timestamp,
            .formatted_time = formatted_time,
            .status = status,
        };
    }

    pub fn deinit(self: *DDSMessageDisplay, alloc: std.mem.Allocator) void {
        alloc.free(self.content);
        alloc.free(self.formatted_time);
    }
};

// Progress Bar Component
const ProgressBar = struct {
    current: f32,
    max: f32,
    width: u16,

    pub fn init(width: u16) ProgressBar {
        return ProgressBar{
            .current = 0.0,
            .max = 100.0,
            .width = width,
        };
    }

    pub fn setProgress(self: *ProgressBar, current: f32, max: f32) void {
        self.current = current;
        self.max = max;
    }

    pub fn render(self: *ProgressBar, alloc: std.mem.Allocator) ![]const u8 {
        const percentage = if (self.max > 0) (self.current / self.max) else 0.0;
        const filled_width = @as(u16, @intFromFloat(@as(f32, @floatFromInt(self.width)) * percentage));
        const empty_width = self.width - filled_width;

        var progress_str = std.ArrayList(u8).init(alloc);
        defer progress_str.deinit();

        for (0..filled_width) |_| {
            try progress_str.appendSlice("█");
        }
        for (0..empty_width) |_| {
            try progress_str.appendSlice("░");
        }

        return try progress_str.toOwnedSlice();
    }
};

pub const panic = vaxis.panic_handler;

pub fn main() !void {
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.detectLeaks()) std.log.err("Memory leak detected!", .{});
    const alloc = gpa.allocator();

    // Initialize DDS system (using mock for demonstration)
    var mock_dds = fastdds.MockDDSSystem.init(alloc);
    defer mock_dds.deinit();
    var mock_subscriber = mock_dds.createSubscriber();
    var mock_publisher = mock_dds.createPublisher();

    // Initialize DDS message storage
    var dds_messages = std.ArrayList(DDSMessageDisplay).init(alloc);
    defer {
        for (dds_messages.items) |*msg| {
            msg.deinit(alloc);
        }
        dds_messages.deinit();
    }

    // Message ID counter
    var message_id_counter: u32 = 0;

    // Initialize progress bar
    var progress_bar = ProgressBar.init(50);

    // Initialize users data (keep for comparison)
    const users_buf = try alloc.dupe(User, users[0..]);
    defer alloc.free(users_buf);
    var user_mal = std.MultiArrayList(User){};
    for (users_buf[0..]) |user| try user_mal.append(alloc, user);
    defer user_mal.deinit(alloc);

    // Create DDS message MultiArrayList for table display
    var dds_mal = std.MultiArrayList(DDSMessageDisplay){};
    defer dds_mal.deinit(alloc);

    var tty = try vaxis.Tty.init();
    defer tty.deinit();
    var tty_buf_writer = tty.bufferedWriter();
    defer tty_buf_writer.flush() catch {};
    const tty_writer = tty_buf_writer.writer().any();

    var vx = try vaxis.init(alloc, .{
        .kitty_keyboard_flags = .{ .report_events = true },
    });
    defer vx.deinit(alloc, tty.anyWriter());

    var loop: vaxis.Loop(Event) = .{ .tty = &tty, .vaxis = &vx };
    try loop.init();
    try loop.start();
    defer loop.stop();
    try vx.enterAltScreen(tty.anyWriter());
    try vx.queryTerminal(tty.anyWriter(), 250 * std.time.ns_per_ms);

    // Colors
    const primary_blue: vaxis.Cell.Color = .{ .rgb = .{ 64, 128, 255 } };
    const accent_cyan: vaxis.Cell.Color = .{ .rgb = .{ 100, 200, 255 } };
    const success_green: vaxis.Cell.Color = .{ .rgb = .{ 100, 255, 100 } };
    const warning_yellow: vaxis.Cell.Color = .{ .rgb = .{ 255, 200, 100 } };
    const danger_red: vaxis.Cell.Color = .{ .rgb = .{ 255, 100, 100 } };
    const dark_bg: vaxis.Cell.Color = .{ .rgb = .{ 16, 16, 24 } };
    const darker_bg: vaxis.Cell.Color = .{ .rgb = .{ 8, 8, 16 } };
    const medium_bg: vaxis.Cell.Color = .{ .rgb = .{ 32, 32, 48 } };
    const detail_bg: vaxis.Cell.Color = .{ .rgb = .{ 24, 24, 36 } };

    // Table Context for DDS Messages
    var dds_tbl: vaxis.widgets.Table.TableContext = .{
        .active_bg = primary_blue,
        .active_fg = .{ .rgb = .{ 0, 0, 0 } },
        .row_bg_1 = dark_bg,
        .row_bg_2 = darker_bg,
        .selected_bg = accent_cyan,
        .header_names = .{ .custom = &.{ "ID", "Content", "Time", "Status" } },
        .col_indexes = .{ .by_idx = &.{ 0, 1, 2, 3 } },
        .col_width = .{ .static_individual = &.{ 8, 35, 12, 15 } },
        .header_borders = true,
        .col_borders = true,
    };
    defer if (dds_tbl.sel_rows) |rows| alloc.free(rows);

    // Table Context for Users (backup)
    var demo_tbl: vaxis.widgets.Table.TableContext = .{
        .active_bg = primary_blue,
        .active_fg = .{ .rgb = .{ 0, 0, 0 } },
        .row_bg_1 = dark_bg,
        .row_bg_2 = darker_bg,
        .selected_bg = accent_cyan,
        .header_names = .{ .custom = &.{ "First", "Last", "Username", "Status" } },
        .col_indexes = .{ .by_idx = &.{ 0, 1, 2, 3 } },
        .col_width = .{ .static_individual = &.{ 12, 15, 18, 12 } },
        .header_borders = true,
        .col_borders = true,
    };
    defer if (demo_tbl.sel_rows) |rows| alloc.free(rows);

    // State
    var selected_user_idx: usize = 0;
    var selected_message_idx: usize = 0;
    var show_help = false;
    var animation_frame: u32 = 0;
    var current_tab: usize = 0;
    const tab_names = [_][]const u8{ "📡 DDS Messages", "👥 Users", "📊 Analytics", "⚙️ Settings" };

    // Mock message generation
    var last_message_time: u64 = 0;
    const message_interval: u64 = 1000; // Generate message every 1000ms

    // Create an Arena Allocator for easy allocations on each Event.
    var event_arena = heap.ArenaAllocator.init(alloc);
    defer event_arena.deinit();

    while (true) {
        defer _ = event_arena.reset(.retain_capacity);
        defer tty_buf_writer.flush() catch {};
        const event_alloc = event_arena.allocator();

        // Animation frame counter
        animation_frame += 1;

        // Generate mock DDS messages periodically
        const current_time: u64 = @intCast(std.time.milliTimestamp());
        if (current_time - last_message_time > message_interval) {
            last_message_time = current_time;

            // Create mock messages
            const mock_messages = [_][]const u8{
                "Sensor temperature: 23.5°C",
                "GPS coordinates: 40.7128, -74.0060",
                "System status: All systems operational",
                "Battery level: 85%",
                "Network connectivity: Strong",
                "Memory usage: 45%",
                "CPU load: 12%",
                "Disk space: 78% used",
                "Active connections: 42",
                "Data throughput: 1.2 MB/s",
            };

            const content = mock_messages[animation_frame % mock_messages.len];
            const mock_message = fastdds.DDSMessage.init(content, @intCast(current_time));

            // Publish to mock system
            try mock_publisher.publish(mock_message);

            // Try to receive and add to our display list
            if (mock_subscriber.receive()) |received_msg| {
                const display_msg = try DDSMessageDisplay.fromDDSMessage(alloc, received_msg, message_id_counter);
                try dds_messages.append(display_msg);
                try dds_mal.append(alloc, display_msg);
                message_id_counter += 1;

                // Update progress bar (simulate processing progress)
                progress_bar.setProgress(@floatFromInt(dds_messages.items.len % 20), 20.0);

                // Keep only last 50 messages for display
                if (dds_messages.items.len > 50) {
                    var old_msg = dds_messages.orderedRemove(0);
                    old_msg.deinit(alloc);
                    _ = dds_mal.orderedRemove(0);
                }
            }
        }

        // Poll for events with a small timeout to enable animation
        const event = loop.tryEvent() orelse {
            // No event, just animate and continue
            std.time.sleep(50 * std.time.ns_per_ms);
            continue;
        };

        switch (event) {
            .key_press => |key| {
                // Close the Program
                if (key.matches('c', .{ .ctrl = true })) break;

                // Toggle Help - FIXED: removed continue so rendering happens immediately
                if (key.matches('h', .{}) or key.matches('?', .{})) {
                    show_help = !show_help;
                }

                // Tab Navigation
                if (key.matches(vaxis.Key.tab, .{})) {
                    current_tab = (current_tab + 1) % tab_names.len;
                }
                if (key.matches(vaxis.Key.tab, .{ .shift = true })) {
                    current_tab = if (current_tab == 0) tab_names.len - 1 else current_tab - 1;
                }
                // Direct tab access with number keys
                if (key.matches('1', .{})) current_tab = 0;
                if (key.matches('2', .{})) current_tab = 1;
                if (key.matches('3', .{})) current_tab = 2;
                if (key.matches('4', .{})) current_tab = 3;

                // Refresh
                if (key.matches('r', .{})) {
                    animation_frame = 0; // Reset animation
                }

                // Navigation based on current tab
                if (key.matchesAny(&.{ vaxis.Key.up, 'k' }, .{})) {
                    if (current_tab == 0) { // DDS Messages tab
                        dds_tbl.row -|= 1;
                        selected_message_idx = dds_tbl.row;
                    } else if (current_tab == 1) { // Users tab
                        demo_tbl.row -|= 1;
                        selected_user_idx = demo_tbl.row;
                    }
                }
                if (key.matchesAny(&.{ vaxis.Key.down, 'j' }, .{})) {
                    if (current_tab == 0) { // DDS Messages tab
                        if (dds_messages.items.len > 0) {
                            dds_tbl.row = @min(dds_tbl.row + 1, dds_messages.items.len - 1);
                            selected_message_idx = dds_tbl.row;
                        }
                    } else if (current_tab == 1) { // Users tab
                        demo_tbl.row = @min(demo_tbl.row + 1, users_buf.len - 1);
                        selected_user_idx = demo_tbl.row;
                    }
                }

                // Page navigation
                if (key.matches(vaxis.Key.page_up, .{}) or key.matches('u', .{ .ctrl = true })) {
                    if (current_tab == 0) { // DDS Messages tab
                        dds_tbl.row = if (dds_tbl.row >= 10) dds_tbl.row - 10 else 0;
                        selected_message_idx = dds_tbl.row;
                    } else if (current_tab == 1) { // Users tab
                        demo_tbl.row = if (demo_tbl.row >= 10) demo_tbl.row - 10 else 0;
                        selected_user_idx = demo_tbl.row;
                    }
                }
                if (key.matches(vaxis.Key.page_down, .{}) or key.matches('d', .{ .ctrl = true })) {
                    if (current_tab == 0) { // DDS Messages tab
                        if (dds_messages.items.len > 0) {
                            dds_tbl.row = @min(dds_tbl.row + 10, dds_messages.items.len - 1);
                            selected_message_idx = dds_tbl.row;
                        }
                    } else if (current_tab == 1) { // Users tab
                        demo_tbl.row = @min(demo_tbl.row + 10, users_buf.len - 1);
                        selected_user_idx = demo_tbl.row;
                    }
                }

                // Go to top/bottom
                if (key.matches('g', .{})) {
                    if (current_tab == 0) { // DDS Messages tab
                        dds_tbl.row = 0;
                        selected_message_idx = 0;
                    } else if (current_tab == 1) { // Users tab
                        demo_tbl.row = 0;
                        selected_user_idx = 0;
                    }
                }
                if (key.matches('G', .{})) {
                    if (current_tab == 0) { // DDS Messages tab
                        if (dds_messages.items.len > 0) {
                            dds_tbl.row = @intCast(dds_messages.items.len - 1);
                            selected_message_idx = dds_messages.items.len - 1;
                        }
                    } else if (current_tab == 1) { // Users tab
                        demo_tbl.row = @intCast(users_buf.len - 1);
                        selected_user_idx = users_buf.len - 1;
                    }
                }

                // Select/Unselect Row
                if (key.matches(vaxis.Key.space, .{})) {
                    if (current_tab == 0) { // DDS Messages tab
                        const rows = dds_tbl.sel_rows orelse createRows: {
                            dds_tbl.sel_rows = try alloc.alloc(u16, 1);
                            break :createRows dds_tbl.sel_rows.?;
                        };
                        var rows_list = std.ArrayList(u16).fromOwnedSlice(alloc, rows);
                        for (rows_list.items, 0..) |row, idx| {
                            if (row != dds_tbl.row) continue;
                            _ = rows_list.orderedRemove(idx);
                            break;
                        } else try rows_list.append(dds_tbl.row);
                        dds_tbl.sel_rows = try rows_list.toOwnedSlice();
                    } else if (current_tab == 1) { // Users tab
                        const rows = demo_tbl.sel_rows orelse createRows: {
                            demo_tbl.sel_rows = try alloc.alloc(u16, 1);
                            break :createRows demo_tbl.sel_rows.?;
                        };
                        var rows_list = std.ArrayList(u16).fromOwnedSlice(alloc, rows);
                        for (rows_list.items, 0..) |row, idx| {
                            if (row != demo_tbl.row) continue;
                            _ = rows_list.orderedRemove(idx);
                            break;
                        } else try rows_list.append(demo_tbl.row);
                        demo_tbl.sel_rows = try rows_list.toOwnedSlice();
                    }
                }

                // Clear selections
                if (key.matches('c', .{})) {
                    if (current_tab == 0) { // DDS Messages tab
                        if (dds_tbl.sel_rows) |rows| {
                            alloc.free(rows);
                            dds_tbl.sel_rows = null;
                        }
                    } else if (current_tab == 1) { // Users tab
                        if (demo_tbl.sel_rows) |rows| {
                            alloc.free(rows);
                            demo_tbl.sel_rows = null;
                        }
                    }
                }
            },
            .winsize => |ws| try vx.resize(alloc, tty.anyWriter(), ws),
        }

        // Render
        const win = vx.window();
        win.clear();

        // Calculate layout dimensions with tabs
        const tab_height: u16 = 3;
        const controls_height: u16 = if (show_help) 6 else 3;
        const content_height = win.height - controls_height - tab_height;
        const split_width = win.width / 2;

        // Title Bar
        const title_bar = win.child(.{
            .height = 1,
        });
        title_bar.fill(.{ .style = .{ .bg = primary_blue } });
        const title_text = try fmt.allocPrint(event_alloc, "┃ VAXIS DEMO - USER MANAGEMENT SYSTEM ┃ Frame: {d:0>6} ┃ Press 'h' for help", .{animation_frame});
        const title_segments = [_]vaxis.Cell.Segment{
            .{ .text = title_text, .style = .{ .bg = primary_blue, .bold = true, .fg = .{ .rgb = .{ 255, 255, 255 } } } },
        };
        _ = title_bar.print(&title_segments, .{});

        // Tab Bar
        var tab_bar = win.child(.{
            .y_off = 1,
            .height = tab_height,
        });
        try renderTabBar(event_alloc, &tab_bar, current_tab, &tab_names, primary_blue, accent_cyan, success_green, warning_yellow);

        // Main Content Area (below tabs)
        var main_content = win.child(.{
            .y_off = tab_height + 1,
            .height = content_height,
        });

        // Render tab content
        switch (current_tab) {
            0 => try renderDDSMessagesTab(event_alloc, &main_content, &dds_tbl, dds_mal, dds_messages.items, selected_message_idx, animation_frame, split_width, content_height, accent_cyan, warning_yellow, detail_bg, success_green, primary_blue, &progress_bar),
            1 => try renderUsersTab(event_alloc, &main_content, &demo_tbl, user_mal, users_buf, selected_user_idx, animation_frame, split_width, content_height, accent_cyan, warning_yellow, detail_bg, success_green, primary_blue),
            2 => try renderAnalyticsTab(event_alloc, &main_content, dds_messages.items, animation_frame, primary_blue, success_green, warning_yellow, danger_red),
            3 => try renderSettingsTab(event_alloc, &main_content, animation_frame, medium_bg, accent_cyan, success_green),
            else => {},
        }

        // Old rendering code removed - now handled by tab functions

        // Controls at the bottom
        const controls = win.child(.{
            .y_off = content_height,
            .height = controls_height,
        });
        controls.fill(.{ .style = .{ .bg = medium_bg } });

        if (show_help) {
            const help_segments = [_]vaxis.Cell.Segment{
                .{ .text = "┃ HELP & CONTROLS", .style = .{ .bg = medium_bg, .bold = true, .ul_style = .single, .fg = warning_yellow } },
                .{ .text = " ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", .style = .{ .bg = medium_bg, .fg = warning_yellow } },
                .{ .text = " Navigation:  ↑↓ / j,k    │  Page Up/Down: PgUp/PgDn, Ctrl+u/d  │  Top/Bottom: g/G", .style = .{ .bg = medium_bg, .fg = .{ .rgb = .{ 200, 200, 200 } } } },
                .{ .text = " Selection:   Space       │  Clear: c                            │  Help: h/?", .style = .{ .bg = medium_bg, .fg = .{ .rgb = .{ 200, 200, 200 } } } },
                .{ .text = " Exit:        Ctrl+C      │  Live data with animated UI!", .style = .{ .bg = medium_bg, .fg = .{ .rgb = .{ 150, 255, 150 } }, .italic = true } },
                .{ .text = " ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", .style = .{ .bg = medium_bg, .fg = warning_yellow } },
            };
            _ = controls.print(&help_segments, .{ .wrap = .word });
        } else {
            const RowInfo = struct { row: usize, total: usize, selected: usize };
            const row_info: RowInfo = if (current_tab == 0)
                .{ .row = dds_tbl.row + 1, .total = dds_messages.items.len, .selected = if (dds_tbl.sel_rows != null) dds_tbl.sel_rows.?.len else 0 }
            else
                .{ .row = demo_tbl.row + 1, .total = users_buf.len, .selected = if (demo_tbl.sel_rows != null) demo_tbl.sel_rows.?.len else 0 };

            const status_text = try fmt.allocPrint(event_alloc, "┃ {s} │ Row: {d}/{d} │ Selected: {d} │ Tab: {d}/4 │ Help: h │ Exit: Ctrl+C", .{ tab_names[current_tab], row_info.row, row_info.total, row_info.selected, current_tab + 1 });
            const status_segments = [_]vaxis.Cell.Segment{
                .{ .text = status_text, .style = .{ .bg = medium_bg, .fg = .{ .rgb = .{ 200, 200, 200 } } } },
                .{ .text = " ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", .style = .{ .bg = medium_bg, .fg = primary_blue } },
                .{ .text = " Press 'h' for detailed help and controls. This is a live demonstration of libvaxis capabilities!", .style = .{ .bg = medium_bg, .fg = .{ .rgb = .{ 150, 150, 150 } }, .italic = true } },
            };
            _ = controls.print(&status_segments, .{});
        }

        // Render the screen
        try vx.render(tty_writer);
    }
}

// Tab Bar Rendering Function
fn renderTabBar(alloc: std.mem.Allocator, win: *vaxis.Window, current_tab: usize, tab_names: []const []const u8, primary_blue: vaxis.Cell.Color, accent_cyan: vaxis.Cell.Color, _: vaxis.Cell.Color, _: vaxis.Cell.Color) !void {
    // Tab bar background
    win.fill(.{ .style = .{ .bg = .{ .rgb = .{ 24, 24, 32 } } } });

    const tab_width = win.width / @as(u16, @intCast(tab_names.len));

    for (tab_names, 0..) |tab_name, i| {
        const is_active = i == current_tab;
        const tab_win = win.child(.{
            .x_off = @as(u16, @intCast(i)) * tab_width,
            .width = tab_width,
            .height = 2,
        });

        const tab_color: vaxis.Cell.Color = if (is_active) primary_blue else .{ .rgb = .{ 48, 48, 64 } };
        const text_color: vaxis.Cell.Color = if (is_active) .{ .rgb = .{ 255, 255, 255 } } else .{ .rgb = .{ 180, 180, 180 } };

        tab_win.fill(.{ .style = .{ .bg = tab_color } });

        const tab_text = try fmt.allocPrint(alloc, " {s} [{d}]", .{ tab_name, i + 1 });
        const tab_segments = [_]vaxis.Cell.Segment{
            .{ .text = tab_text, .style = .{ .bg = tab_color, .bold = is_active, .fg = text_color } },
        };
        _ = tab_win.print(&tab_segments, .{ .row_offset = 0, .col_offset = 2 });

        // Tab separator
        if (i < tab_names.len - 1) {
            const sep_win = win.child(.{
                .x_off = @as(u16, @intCast(i + 1)) * tab_width - 1,
                .width = 1,
                .height = 2,
            });
            sep_win.fill(.{ .char = .{ .grapheme = "┃", .width = 1 }, .style = .{ .fg = accent_cyan } });
        }
    }

    // Bottom tab bar border
    const border_win = win.child(.{
        .y_off = 2,
        .height = 1,
    });
    const border_text = "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━";
    const border_segments = [_]vaxis.Cell.Segment{
        .{ .text = border_text, .style = .{ .fg = primary_blue } },
    };
    _ = border_win.print(&border_segments, .{});
}

// DDS Messages Tab - Shows live DDS messages with progress bar
fn renderDDSMessagesTab(alloc: std.mem.Allocator, win: *vaxis.Window, dds_tbl: *vaxis.widgets.Table.TableContext, dds_mal: std.MultiArrayList(DDSMessageDisplay), dds_messages: []const DDSMessageDisplay, selected_message_idx: usize, animation_frame: u32, split_width: u16, content_height: u16, accent_cyan: vaxis.Cell.Color, warning_yellow: vaxis.Cell.Color, detail_bg: vaxis.Cell.Color, success_green: vaxis.Cell.Color, primary_blue: vaxis.Cell.Color, progress_bar: *ProgressBar) !void {
    // Left Pane: DDS Messages Table
    const left_pane = win.child(.{
        .x_off = 0,
        .y_off = 0,
        .width = split_width,
        .height = content_height,
    });

    // Table header with progress bar
    const table_header = left_pane.child(.{
        .height = 3,
    });
    table_header.fill(.{ .style = .{ .bg = accent_cyan, .bold = true } });

    const header_text = try fmt.allocPrint(alloc, "┃ LIVE DDS MESSAGES ({d} total)", .{dds_messages.len});
    const table_header_segments = [_]vaxis.Cell.Segment{
        .{ .text = header_text, .style = .{ .bg = accent_cyan, .bold = true, .fg = .{ .rgb = .{ 0, 0, 0 } } } },
    };
    _ = table_header.print(&table_header_segments, .{});

    // Progress bar
    const progress_text = try progress_bar.render(alloc);
    defer alloc.free(progress_text);
    const progress_segments = [_]vaxis.Cell.Segment{
        .{ .text = "Processing: ", .style = .{ .bg = accent_cyan, .fg = .{ .rgb = .{ 0, 0, 0 } } } },
        .{ .text = progress_text, .style = .{ .bg = accent_cyan, .fg = success_green } },
        .{ .text = try fmt.allocPrint(alloc, " {d:.1}%", .{(progress_bar.current / progress_bar.max) * 100}), .style = .{ .bg = accent_cyan, .fg = .{ .rgb = .{ 0, 0, 0 } } } },
    };
    _ = table_header.print(&progress_segments, .{ .row_offset = 1 });

    // Table content
    const table_content = left_pane.child(.{
        .y_off = 3,
        .height = content_height - 3,
    });

    if (dds_messages.len > 0) {
        dds_tbl.active = true;
        try vaxis.widgets.Table.drawTable(
            alloc,
            table_content,
            dds_mal,
            dds_tbl,
        );
    } else {
        const no_data_segments = [_]vaxis.Cell.Segment{
            .{ .text = "No DDS messages received yet...", .style = .{ .fg = .{ .rgb = .{ 150, 150, 150 } }, .italic = true } },
            .{ .text = "\nWaiting for FastDDS data...", .style = .{ .fg = warning_yellow } },
        };
        _ = table_content.print(&no_data_segments, .{ .row_offset = 2, .col_offset = 2 });
    }

    // Animated separator
    const separator = win.child(.{
        .x_off = split_width,
        .y_off = 0,
        .width = 1,
        .height = content_height,
    });
    const separator_colors = [_]vaxis.Cell.Color{ primary_blue, accent_cyan, success_green };
    const sep_color = separator_colors[animation_frame / 20 % separator_colors.len];
    separator.fill(.{ .char = .{ .grapheme = "┃", .width = 1 }, .style = .{ .fg = sep_color } });

    // Right Pane: Message Details
    const right_pane = win.child(.{
        .x_off = split_width + 1,
        .y_off = 0,
        .width = win.width - split_width - 1,
        .height = content_height,
    });

    // Detail header
    const detail_header = right_pane.child(.{
        .height = 1,
    });
    detail_header.fill(.{ .style = .{ .bg = warning_yellow, .bold = true } });
    const detail_header_segments = [_]vaxis.Cell.Segment{
        .{ .text = "┃ MESSAGE DETAILS & ANALYTICS", .style = .{ .bg = warning_yellow, .bold = true, .fg = .{ .rgb = .{ 0, 0, 0 } } } },
    };
    _ = detail_header.print(&detail_header_segments, .{});

    // Detail content
    const detail_content = right_pane.child(.{
        .y_off = 1,
        .height = content_height - 1,
    });
    detail_content.fill(.{ .style = .{ .bg = detail_bg } });

    if (selected_message_idx < dds_messages.len) {
        const message = dds_messages[selected_message_idx];
        const detail_segments = try createDDSMessageDetailSegments(alloc, message, selected_message_idx, animation_frame, dds_tbl.sel_rows);
        _ = detail_content.print(detail_segments, .{ .wrap = .word });
    } else if (dds_messages.len > 0) {
        const no_selection_segments = [_]vaxis.Cell.Segment{
            .{ .text = "\n  📡 SELECT A MESSAGE", .style = .{ .bold = true, .fg = accent_cyan } },
            .{ .text = "\n  Use ↑↓ keys to navigate through messages", .style = .{ .fg = .{ .rgb = .{ 150, 150, 150 } } } },
        };
        _ = detail_content.print(&no_selection_segments, .{});
    }
}

// Users Tab - Enhanced split view with table and details
fn renderUsersTab(alloc: std.mem.Allocator, win: *vaxis.Window, demo_tbl: *vaxis.widgets.Table.TableContext, user_mal: std.MultiArrayList(User), users_buf: []const User, selected_user_idx: usize, animation_frame: u32, split_width: u16, content_height: u16, accent_cyan: vaxis.Cell.Color, warning_yellow: vaxis.Cell.Color, detail_bg: vaxis.Cell.Color, success_green: vaxis.Cell.Color, primary_blue: vaxis.Cell.Color) !void {
    // Left Pane: Table
    const left_pane = win.child(.{
        .x_off = 0,
        .y_off = 0,
        .width = split_width,
        .height = content_height,
    });

    // Table header
    const table_header = left_pane.child(.{
        .height = 1,
    });
    table_header.fill(.{ .style = .{ .bg = accent_cyan, .bold = true } });
    const table_header_segments = [_]vaxis.Cell.Segment{
        .{ .text = "┃ USER DATABASE", .style = .{ .bg = accent_cyan, .bold = true, .fg = .{ .rgb = .{ 0, 0, 0 } } } },
    };
    _ = table_header.print(&table_header_segments, .{});

    // Table content
    const table_content = left_pane.child(.{
        .y_off = 1,
        .height = content_height - 1,
    });

    if (users_buf.len > 0) {
        demo_tbl.active = true;
        try vaxis.widgets.Table.drawTable(
            alloc,
            table_content,
            user_mal,
            demo_tbl,
        );
    }

    // Animated separator
    const separator = win.child(.{
        .x_off = split_width,
        .y_off = 0,
        .width = 1,
        .height = content_height,
    });
    const separator_colors = [_]vaxis.Cell.Color{ primary_blue, accent_cyan, success_green };
    const sep_color = separator_colors[animation_frame / 20 % separator_colors.len];
    separator.fill(.{ .char = .{ .grapheme = "┃", .width = 1 }, .style = .{ .fg = sep_color } });

    // Right Pane: User Details
    const right_pane = win.child(.{
        .x_off = split_width + 1,
        .y_off = 0,
        .width = win.width - split_width - 1,
        .height = content_height,
    });

    // Detail header
    const detail_header = right_pane.child(.{
        .height = 1,
    });
    detail_header.fill(.{ .style = .{ .bg = warning_yellow, .bold = true } });
    const detail_header_segments = [_]vaxis.Cell.Segment{
        .{ .text = "┃ USER DETAILS & ANALYTICS", .style = .{ .bg = warning_yellow, .bold = true, .fg = .{ .rgb = .{ 0, 0, 0 } } } },
    };
    _ = detail_header.print(&detail_header_segments, .{});

    // Detail content
    const detail_content = right_pane.child(.{
        .y_off = 1,
        .height = content_height - 1,
    });
    detail_content.fill(.{ .style = .{ .bg = detail_bg } });

    if (selected_user_idx < users_buf.len) {
        const user = users_buf[selected_user_idx];
        const detail_segments = try createDetailSegments(alloc, user, selected_user_idx, animation_frame, demo_tbl.sel_rows);
        _ = detail_content.print(detail_segments, .{ .wrap = .word });
    }
}

// Analytics Tab - Data visualization and metrics
fn renderAnalyticsTab(alloc: std.mem.Allocator, win: *vaxis.Window, dds_messages: []const DDSMessageDisplay, animation_frame: u32, primary_blue: vaxis.Cell.Color, success_green: vaxis.Cell.Color, warning_yellow: vaxis.Cell.Color, danger_red: vaxis.Cell.Color) !void {
    win.fill(.{ .style = .{ .bg = .{ .rgb = .{ 16, 16, 24 } } } });

    // Analytics Header
    const header = win.child(.{
        .height = 3,
    });
    header.fill(.{ .style = .{ .bg = primary_blue } });
    const header_text = try fmt.allocPrint(alloc, "📊 REAL-TIME DDS ANALYTICS DASHBOARD | Messages: {d} | Frame: {d}", .{ dds_messages.len, animation_frame });
    const header_segments = [_]vaxis.Cell.Segment{
        .{ .text = header_text, .style = .{ .bg = primary_blue, .bold = true, .fg = .{ .rgb = .{ 255, 255, 255 } } } },
    };
    _ = header.print(&header_segments, .{ .row_offset = 1, .col_offset = 2 });

    // Metrics Grid
    const metrics_area = win.child(.{
        .y_off = 3,
        .height = win.height - 3,
    });

    const col_width = win.width / 4;

    // Metric 1: Message Count
    var metric1 = metrics_area.child(.{
        .width = col_width,
        .height = 8,
    });
    try renderMetricCard(alloc, &metric1, "📡 Total Messages", try fmt.allocPrint(alloc, "{d}", .{dds_messages.len}), success_green);

    // Metric 2: Active Sessions (animated)
    var metric2 = metrics_area.child(.{
        .x_off = col_width,
        .width = col_width,
        .height = 8,
    });
    const active_sessions = 45 + (animation_frame / 30) % 20;
    try renderMetricCard(alloc, &metric2, "🟢 Active Sessions", try fmt.allocPrint(alloc, "{d}", .{active_sessions}), warning_yellow);

    // Metric 3: System Load
    var metric3 = metrics_area.child(.{
        .x_off = col_width * 2,
        .width = col_width,
        .height = 8,
    });
    const load = (animation_frame / 10) % 100;
    const load_color = if (load > 80) danger_red else if (load > 60) warning_yellow else success_green;
    try renderMetricCard(alloc, &metric3, "⚡ System Load", try fmt.allocPrint(alloc, "{d}%", .{load}), load_color);

    // Metric 4: Response Time
    var metric4 = metrics_area.child(.{
        .x_off = col_width * 3,
        .width = col_width,
        .height = 8,
    });
    const response_time = 15 + (animation_frame / 40) % 10;
    try renderMetricCard(alloc, &metric4, "⏱️ Avg Response", try fmt.allocPrint(alloc, "{d}ms", .{response_time}), primary_blue);

    // Real-time chart area
    var chart_area = metrics_area.child(.{
        .y_off = 8,
        .height = metrics_area.height - 8,
    });
    try renderChart(alloc, &chart_area, animation_frame, primary_blue, success_green, warning_yellow);
}

// Settings Tab - Configuration and preferences
fn renderSettingsTab(_: std.mem.Allocator, win: *vaxis.Window, _: u32, medium_bg: vaxis.Cell.Color, accent_cyan: vaxis.Cell.Color, _: vaxis.Cell.Color) !void {
    win.fill(.{ .style = .{ .bg = medium_bg } });

    const header = win.child(.{
        .height = 2,
    });
    header.fill(.{ .style = .{ .bg = accent_cyan } });
    const header_segments = [_]vaxis.Cell.Segment{
        .{ .text = "⚙️ SYSTEM SETTINGS & CONFIGURATION", .style = .{ .bg = accent_cyan, .bold = true, .fg = .{ .rgb = .{ 0, 0, 0 } } } },
    };
    _ = header.print(&header_segments, .{ .row_offset = 0, .col_offset = 2 });

    const content = win.child(.{
        .y_off = 2,
        .height = win.height - 2,
    });

    const settings_text = "  🎨 DISPLAY SETTINGS\n" ++
        "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n" ++
        "  \n" ++
        "  • Theme: Dark Mode ✓\n" ++
        "  • Animation Speed: 75%\n" ++
        "  • Color Scheme: Professional Blue\n" ++
        "  • Font Size: Medium\n" ++
        "  • Border Style: Unicode\n" ++
        "  \n" ++
        "  🔧 SYSTEM PREFERENCES\n" ++
        "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n" ++
        "  \n" ++
        "  • Auto-refresh: Enabled\n" ++
        "  • Sound Effects: Disabled\n" ++
        "  • Mouse Support: Enabled\n" ++
        "  • Keyboard Shortcuts: Vim-style\n" ++
        "  • Debug Mode: Off\n" ++
        "  \n" ++
        "  📊 DATA MANAGEMENT\n" ++
        "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n" ++
        "  \n" ++
        "  • Cache Size: 50MB\n" ++
        "  • Auto-save: Every 5 minutes\n" ++
        "  • Backup Location: ~/backups\n" ++
        "  • Export Format: JSON\n" ++
        "  • Compression: Enabled\n" ++
        "  \n" ++
        "  Press 'Tab' to switch between sections...";

    const settings_segments = [_]vaxis.Cell.Segment{
        .{ .text = settings_text, .style = .{ .fg = .{ .rgb = .{ 200, 200, 200 } } } },
    };
    _ = content.print(&settings_segments, .{ .wrap = .word });
}

// Reports Tab - Data reports and exports
fn renderReportsTab(alloc: std.mem.Allocator, win: *vaxis.Window, users_buf: []const User, animation_frame: u32, _: vaxis.Cell.Color, warning_yellow: vaxis.Cell.Color, _: vaxis.Cell.Color) !void {
    win.fill(.{ .style = .{ .bg = .{ .rgb = .{ 20, 20, 30 } } } });

    const header = win.child(.{
        .height = 2,
    });
    header.fill(.{ .style = .{ .bg = warning_yellow } });
    const header_segments = [_]vaxis.Cell.Segment{
        .{ .text = "📈 REPORTS & DATA EXPORT", .style = .{ .bg = warning_yellow, .bold = true, .fg = .{ .rgb = .{ 0, 0, 0 } } } },
    };
    _ = header.print(&header_segments, .{ .row_offset = 0, .col_offset = 2 });

    const content = win.child(.{
        .y_off = 2,
        .height = win.height - 2,
    });

    const report_time = try fmt.allocPrint(alloc, "{d:0>2}:{d:0>2}:{d:0>2}", .{ (animation_frame / 100) % 24, (animation_frame / 10) % 60, animation_frame % 60 });

    const reports_text = try fmt.allocPrint(alloc, "  📋 AVAILABLE REPORTS\n" ++
        "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n" ++
        "  \n" ++
        "  📊 User Activity Report        [Generate] [Schedule]\n" ++
        "     • Total users: {d}\n" ++
        "     • Active sessions: {d}\n" ++
        "     • Last updated: {s}\n" ++
        "  \n" ++
        "  📈 Performance Metrics         [Generate] [Schedule]\n" ++
        "     • System uptime: 99.9%\n" ++
        "     • Response time: <25ms\n" ++
        "     • Memory usage: 45%\n" ++
        "  \n" ++
        "  🔐 Security Audit              [Generate] [Schedule]\n" ++
        "     • Failed logins: 3\n" ++
        "     • Password changes: 12\n" ++
        "     • Admin actions: 45\n" ++
        "  \n" ++
        "  📤 DATA EXPORT OPTIONS\n" ++
        "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n" ++
        "  \n" ++
        "  • Format: [CSV] [JSON] [XML] [PDF]\n" ++
        "  • Date Range: Last 30 days\n" ++
        "  • Include: All fields\n" ++
        "  • Compression: Enabled\n" ++
        "  \n" ++
        "  📅 SCHEDULED REPORTS\n" ++
        "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n" ++
        "  \n" ++
        "  • Daily Summary: 9:00 AM ✓\n" ++
        "  • Weekly Report: Monday 8:00 AM ✓\n" ++
        "  • Monthly Analysis: 1st of month ✓\n" ++
        "  \n" ++
        "  Last generated: {s} | Next: Tomorrow 9:00 AM", .{ users_buf.len, 45 + (animation_frame / 30) % 20, report_time, report_time });

    const reports_segments = [_]vaxis.Cell.Segment{
        .{ .text = reports_text, .style = .{ .fg = .{ .rgb = .{ 200, 200, 200 } } } },
    };
    _ = content.print(&reports_segments, .{ .wrap = .word });
}

// Helper function for metric cards
fn renderMetricCard(_: std.mem.Allocator, win: *vaxis.Window, title: []const u8, value: []const u8, color: vaxis.Cell.Color) !void {
    win.fill(.{ .style = .{ .bg = .{ .rgb = .{ 32, 32, 48 } } } });

    // Card border
    const border_win = win.child(.{
        .width = win.width - 2,
        .height = win.height - 1,
        .x_off = 1,
        .y_off = 0,
        .border = .{ .where = .all, .style = .{ .fg = color } },
    });

    // Title
    const title_segments = [_]vaxis.Cell.Segment{
        .{ .text = title, .style = .{ .fg = color, .bold = true } },
    };
    _ = border_win.print(&title_segments, .{ .row_offset = 1, .col_offset = 2 });

    // Value
    const value_segments = [_]vaxis.Cell.Segment{
        .{ .text = value, .style = .{ .fg = .{ .rgb = .{ 255, 255, 255 } }, .bold = true } },
    };
    _ = border_win.print(&value_segments, .{ .row_offset = 3, .col_offset = 2 });
}

// Helper function for charts
fn renderChart(alloc: std.mem.Allocator, win: *vaxis.Window, animation_frame: u32, primary_blue: vaxis.Cell.Color, success_green: vaxis.Cell.Color, warning_yellow: vaxis.Cell.Color) !void {
    win.fill(.{ .style = .{ .bg = .{ .rgb = .{ 24, 24, 36 } } } });

    const chart_header = win.child(.{
        .height = 2,
    });
    chart_header.fill(.{ .style = .{ .bg = primary_blue } });
    const chart_title = "📈 REAL-TIME PERFORMANCE CHART";
    const chart_header_segments = [_]vaxis.Cell.Segment{
        .{ .text = chart_title, .style = .{ .bg = primary_blue, .bold = true, .fg = .{ .rgb = .{ 255, 255, 255 } } } },
    };
    _ = chart_header.print(&chart_header_segments, .{ .row_offset = 0, .col_offset = 2 });

    const chart_content = win.child(.{
        .y_off = 2,
        .height = win.height - 2,
    });

    // Simple ASCII chart
    const chart_width = chart_content.width - 4;
    const chart_line = try alloc.alloc(u8, chart_width);
    defer alloc.free(chart_line);

    for (chart_line, 0..) |*char, i| {
        const height = (50 + @as(u32, @intCast(i)) * 3 + animation_frame / 2) % 100;
        char.* = if (height > 75) '#' else if (height > 50) '=' else if (height > 25) '-' else '.';
    }

    const chart_segments = [_]vaxis.Cell.Segment{
        .{ .text = "CPU: ", .style = .{ .fg = .{ .rgb = .{ 150, 150, 150 } } } },
        .{ .text = chart_line, .style = .{ .fg = success_green } },
        .{ .text = "\nMEM: ", .style = .{ .fg = .{ .rgb = .{ 150, 150, 150 } } } },
        .{ .text = chart_line, .style = .{ .fg = warning_yellow } },
        .{ .text = "\nNET: ", .style = .{ .fg = .{ .rgb = .{ 150, 150, 150 } } } },
        .{ .text = chart_line, .style = .{ .fg = primary_blue } },
    };
    _ = chart_content.print(&chart_segments, .{ .row_offset = 2, .col_offset = 2 });
}

fn createDDSMessageDetailSegments(alloc: std.mem.Allocator, message: DDSMessageDisplay, idx: usize, frame: u32, sel_rows: ?[]u16) ![]const vaxis.Cell.Segment {
    const segments = try alloc.alloc(vaxis.Cell.Segment, 20);
    var seg_idx: usize = 0;

    segments[seg_idx] = .{ .text = "\n", .style = .{} };
    seg_idx += 1;
    segments[seg_idx] = .{ .text = "  📡 DDS MESSAGE DETAILS", .style = .{ .bold = true, .fg = .{ .rgb = .{ 100, 200, 255 } } } };
    seg_idx += 1;
    segments[seg_idx] = .{ .text = "\n  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .style = .{ .fg = .{ .rgb = .{ 100, 200, 255 } } } };
    seg_idx += 1;

    segments[seg_idx] = .{ .text = "  🆔 Message ID:   ", .style = .{ .bold = true, .fg = .{ .rgb = .{ 150, 150, 150 } } } };
    seg_idx += 1;
    segments[seg_idx] = .{ .text = try fmt.allocPrint(alloc, "#{d}\n", .{message.id}), .style = .{ .fg = .{ .rgb = .{ 255, 150, 255 } } } };
    seg_idx += 1;

    segments[seg_idx] = .{ .text = "  📄 Content:      ", .style = .{ .bold = true, .fg = .{ .rgb = .{ 150, 150, 150 } } } };
    seg_idx += 1;
    const content_preview = if (message.content.len > 40)
        try fmt.allocPrint(alloc, "{s}...\n", .{message.content[0..40]})
    else
        try fmt.allocPrint(alloc, "{s}\n", .{message.content});
    segments[seg_idx] = .{ .text = content_preview, .style = .{ .fg = .{ .rgb = .{ 255, 255, 255 } } } };
    seg_idx += 1;

    segments[seg_idx] = .{ .text = "  ⏰ Timestamp:    ", .style = .{ .bold = true, .fg = .{ .rgb = .{ 150, 150, 150 } } } };
    seg_idx += 1;
    segments[seg_idx] = .{ .text = try fmt.allocPrint(alloc, "{s}\n", .{message.formatted_time}), .style = .{ .fg = .{ .rgb = .{ 255, 200, 100 } } } };
    seg_idx += 1;

    segments[seg_idx] = .{ .text = "  📊 Status:       ", .style = .{ .bold = true, .fg = .{ .rgb = .{ 150, 150, 150 } } } };
    seg_idx += 1;
    segments[seg_idx] = .{ .text = try fmt.allocPrint(alloc, "{s}\n\n", .{message.status}), .style = .{ .fg = .{ .rgb = .{ 100, 255, 100 } } } };
    seg_idx += 1;

    segments[seg_idx] = .{ .text = "  📊 LIVE ANALYTICS", .style = .{ .bold = true, .fg = .{ .rgb = .{ 255, 200, 100 } } } };
    seg_idx += 1;
    segments[seg_idx] = .{ .text = "\n  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .style = .{ .fg = .{ .rgb = .{ 255, 200, 100 } } } };
    seg_idx += 1;

    // Message latency simulation
    const latency = (frame / 10 + idx) % 100;
    segments[seg_idx] = .{ .text = "  ⚡ Latency:       ", .style = .{ .bold = true, .fg = .{ .rgb = .{ 150, 150, 150 } } } };
    seg_idx += 1;
    segments[seg_idx] = .{ .text = try fmt.allocPrint(alloc, "{d}ms\n", .{latency}), .style = .{ .fg = if (latency > 50) .{ .rgb = .{ 255, 100, 100 } } else .{ .rgb = .{ 100, 255, 100 } } } };
    seg_idx += 1;

    // Processing time simulation
    const processing_time = (frame / 15 + idx * 3) % 50;
    segments[seg_idx] = .{ .text = "  🔄 Processing:    ", .style = .{ .bold = true, .fg = .{ .rgb = .{ 150, 150, 150 } } } };
    seg_idx += 1;
    segments[seg_idx] = .{ .text = try fmt.allocPrint(alloc, "{d}ms\n\n", .{processing_time}), .style = .{ .fg = .{ .rgb = .{ 200, 200, 255 } } } };
    seg_idx += 1;

    const selection_info = if (sel_rows != null and sel_rows.?.len > 0)
        try fmt.allocPrint(alloc, "  ✓ {d} messages selected for batch processing", .{sel_rows.?.len})
    else
        "  ○ No messages selected - use Space to select";

    segments[seg_idx] = .{ .text = "  📊 SELECTION STATUS\n", .style = .{ .bold = true, .fg = .{ .rgb = .{ 255, 150, 255 } } } };
    seg_idx += 1;
    segments[seg_idx] = .{ .text = selection_info, .style = .{ .fg = .{ .rgb = .{ 200, 200, 200 } } } };
    seg_idx += 1;

    return segments[0..seg_idx];
}

fn createDetailSegments(alloc: std.mem.Allocator, user: User, idx: usize, frame: u32, sel_rows: ?[]u16) ![]const vaxis.Cell.Segment {
    const contact_info = if (user.email != null and user.phone != null)
        try fmt.allocPrint(alloc, "{s} │ {s}", .{ user.email.?, user.phone.? })
    else if (user.email != null)
        try fmt.allocPrint(alloc, "{s}", .{user.email.?})
    else if (user.phone != null)
        try fmt.allocPrint(alloc, "{s}", .{user.phone.?})
    else
        "No contact information available";

    // Dynamic status based on frame for animation
    const status_options = [_][]const u8{ "🟢 Online", "🟡 Away", "🔴 Busy", "🟠 In Meeting" };
    const status = status_options[(idx + frame / 30) % status_options.len];

    // Simulate activity metrics
    const activity_score = (idx * 7 + frame / 10) % 100;
    const login_count = 50 + (idx * 13) % 500;

    const segments = try alloc.alloc(vaxis.Cell.Segment, 25);
    var seg_idx: usize = 0;

    segments[seg_idx] = .{ .text = "\n", .style = .{} };
    seg_idx += 1;
    segments[seg_idx] = .{ .text = "  👤 USER PROFILE", .style = .{ .bold = true, .fg = .{ .rgb = .{ 100, 200, 255 } } } };
    seg_idx += 1;
    segments[seg_idx] = .{ .text = "\n  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .style = .{ .fg = .{ .rgb = .{ 100, 200, 255 } } } };
    seg_idx += 1;

    segments[seg_idx] = .{ .text = "  📝 Name:         ", .style = .{ .bold = true, .fg = .{ .rgb = .{ 150, 150, 150 } } } };
    seg_idx += 1;
    segments[seg_idx] = .{ .text = try fmt.allocPrint(alloc, "{s} {s}\n", .{ user.first, user.last }), .style = .{ .fg = .{ .rgb = .{ 255, 255, 255 } } } };
    seg_idx += 1;

    segments[seg_idx] = .{ .text = "  🔗 Username:      ", .style = .{ .bold = true, .fg = .{ .rgb = .{ 150, 150, 150 } } } };
    seg_idx += 1;
    segments[seg_idx] = .{ .text = try fmt.allocPrint(alloc, "{s}\n", .{user.user}), .style = .{ .fg = .{ .rgb = .{ 100, 255, 100 } } } };
    seg_idx += 1;

    segments[seg_idx] = .{ .text = "  📧 Contact:       ", .style = .{ .bold = true, .fg = .{ .rgb = .{ 150, 150, 150 } } } };
    seg_idx += 1;
    segments[seg_idx] = .{ .text = try fmt.allocPrint(alloc, "{s}\n", .{contact_info}), .style = .{ .fg = .{ .rgb = .{ 255, 200, 100 } } } };
    seg_idx += 1;

    segments[seg_idx] = .{ .text = "  📊 Status:        ", .style = .{ .bold = true, .fg = .{ .rgb = .{ 150, 150, 150 } } } };
    seg_idx += 1;
    segments[seg_idx] = .{ .text = try fmt.allocPrint(alloc, "{s}\n", .{status}), .style = .{ .fg = .{ .rgb = .{ 255, 255, 255 } } } };
    seg_idx += 1;

    segments[seg_idx] = .{ .text = "  🆔 User ID:       ", .style = .{ .bold = true, .fg = .{ .rgb = .{ 150, 150, 150 } } } };
    seg_idx += 1;
    segments[seg_idx] = .{ .text = try fmt.allocPrint(alloc, "#{d:0>5}\n\n", .{idx + 1000}), .style = .{ .fg = .{ .rgb = .{ 255, 150, 255 } } } };
    seg_idx += 1;

    segments[seg_idx] = .{ .text = "  📊 LIVE ANALYTICS", .style = .{ .bold = true, .fg = .{ .rgb = .{ 255, 200, 100 } } } };
    seg_idx += 1;
    segments[seg_idx] = .{ .text = "\n  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .style = .{ .fg = .{ .rgb = .{ 255, 200, 100 } } } };
    seg_idx += 1;

    segments[seg_idx] = .{ .text = "  ⚡ Activity Score: ", .style = .{ .bold = true, .fg = .{ .rgb = .{ 150, 150, 150 } } } };
    seg_idx += 1;
    segments[seg_idx] = .{ .text = try fmt.allocPrint(alloc, "{d}%\n", .{activity_score}), .style = .{ .fg = if (activity_score > 70) .{ .rgb = .{ 100, 255, 100 } } else if (activity_score > 40) .{ .rgb = .{ 255, 255, 100 } } else .{ .rgb = .{ 255, 100, 100 } } } };
    seg_idx += 1;

    segments[seg_idx] = .{ .text = "  📈 Login Count:   ", .style = .{ .bold = true, .fg = .{ .rgb = .{ 150, 150, 150 } } } };
    seg_idx += 1;
    segments[seg_idx] = .{ .text = try fmt.allocPrint(alloc, "{d} times\n", .{login_count}), .style = .{ .fg = .{ .rgb = .{ 200, 200, 255 } } } };
    seg_idx += 1;

    segments[seg_idx] = .{ .text = "  ⏰ Last Seen:     ", .style = .{ .bold = true, .fg = .{ .rgb = .{ 150, 150, 150 } } } };
    seg_idx += 1;
    const time_ago = (frame / 60 + idx) % 60;
    segments[seg_idx] = .{ .text = try fmt.allocPrint(alloc, "{d} minutes ago\n\n", .{time_ago}), .style = .{ .fg = .{ .rgb = .{ 150, 255, 255 } } } };
    seg_idx += 1;

    segments[seg_idx] = .{ .text = "  💼 QUICK ACTIONS", .style = .{ .bold = true, .fg = .{ .rgb = .{ 150, 255, 150 } } } };
    seg_idx += 1;
    segments[seg_idx] = .{ .text = "\n  📞 Call │ 📧 Email │ 📝 Edit │ 🗑️ Delete\n\n", .style = .{ .fg = .{ .rgb = .{ 200, 200, 200 } } } };
    seg_idx += 1;

    const selection_info = if (sel_rows != null and sel_rows.?.len > 0)
        try fmt.allocPrint(alloc, "  ✓ {d} users selected for batch operations", .{sel_rows.?.len})
    else
        "  ○ No users selected - use Space to select";

    segments[seg_idx] = .{ .text = "  📊 SELECTION STATUS\n", .style = .{ .bold = true, .fg = .{ .rgb = .{ 255, 150, 255 } } } };
    seg_idx += 1;
    segments[seg_idx] = .{ .text = selection_info, .style = .{ .fg = .{ .rgb = .{ 200, 200, 200 } } } };
    seg_idx += 1;

    return segments[0..seg_idx];
}

/// User Struct
pub const User = struct {
    first: []const u8,
    last: []const u8,
    user: []const u8,
    email: ?[]const u8 = null,
    phone: ?[]const u8 = null,
};

// Users Array - Sample data with rich information
const users = [_]User{
    .{ .first = "Nancy", .last = "Dudley", .user = "angela73", .email = "nancy.dudley@techcorp.com", .phone = "(555) 123-4567" },
    .{ .first = "Emily", .last = "Thornton", .user = "mrogers", .email = "emily.thornton@email.com", .phone = "(558) 888-8604" },
    .{ .first = "Kyle", .last = "Huff", .user = "xsmith", .email = "kyle.huff@company.com", .phone = "301-127-0801" },
    .{ .first = "Christine", .last = "Dodson", .user = "amandabradley", .email = "christine@sullivan.com", .phone = "(555) 987-6543" },
    .{ .first = "Nathaniel", .last = "Kennedy", .user = "nrobinson", .email = "nat.kennedy@startup.io", .phone = "(555) 456-7890" },
    .{ .first = "Laura", .last = "Leon", .user = "dawnjones", .email = "laura.leon@patel.com", .phone = "183-301-3180" },
    .{ .first = "Patrick", .last = "Landry", .user = "michaelhutchinson", .email = "patrick@medina-wallace.net", .phone = "634-486-6444" },
    .{ .first = "Tammy", .last = "Hall", .user = "jamessmith", .email = "tammy.hall@enterprise.com", .phone = "(926) 810-3385" },
    .{ .first = "Stephanie", .last = "Anderson", .user = "wgillespie", .email = "stephanie@yahoo.com", .phone = "(555) 321-9876" },
    .{ .first = "Jennifer", .last = "Williams", .user = "shawn60", .email = "jennifer.w@agency.com", .phone = "611-385-4771" },
    .{ .first = "Elizabeth", .last = "Ortiz", .user = "jennifer76", .email = "elizabeth@delgado.info", .phone = "(555) 654-3210" },
    .{ .first = "Stacy", .last = "Mays", .user = "scottgonzalez", .email = "stacy.mays@gmail.com", .phone = "(555) 789-0123" },
    .{ .first = "Jennifer", .last = "Smith", .user = "joseph75", .email = "jsmith@hill-moore.net", .phone = "(555) 345-6789" },
    .{ .first = "Gary", .last = "Hammond", .user = "brittany26", .email = "gary.hammond@tech.com", .phone = "(555) 567-8901" },
    .{ .first = "Lisa", .last = "Johnson", .user = "tina28", .email = "lisa.johnson@corp.com", .phone = "850-606-2978" },
    .{ .first = "Zachary", .last = "Hopkins", .user = "vargasmichael", .email = "zach.hopkins@dev.com", .phone = "(555) 234-5678" },
    .{ .first = "Joshua", .last = "Kidd", .user = "ghanna", .email = "josh.kidd@yahoo.com", .phone = "(555) 890-1234" },
    .{ .first = "Dawn", .last = "Jones", .user = "alisonlindsey", .email = "dawn.jones@consulting.com", .phone = "(555) 456-7890" },
    .{ .first = "Monica", .last = "Berry", .user = "barbara40", .email = "monica.berry@hotmail.com", .phone = "(295) 346-6453" },
    .{ .first = "Shannon", .last = "Roberts", .user = "krystal37", .email = "shannon@roberts.com", .phone = "980-920-9386" },
    .{ .first = "Thomas", .last = "Mitchell", .user = "williamscorey", .email = "tom.mitchell@roberts.com", .phone = "(555) 111-2222" },
    .{ .first = "Nicole", .last = "Shaffer", .user = "rogerstroy", .email = "nicole.shaffer@design.com", .phone = "(570) 128-5662" },
    .{ .first = "Edward", .last = "Bennett", .user = "andersonchristina", .email = "ed.bennett@finance.com", .phone = "(555) 333-4444" },
    .{ .first = "Duane", .last = "Howard", .user = "pcarpenter", .email = "duane@parker.net", .phone = "(555) 555-6666" },
    .{ .first = "Mary", .last = "Brown", .user = "kimberlyfrost", .email = "mary.brown@andrews.net", .phone = "(555) 777-8888" },
};
