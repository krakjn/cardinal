const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main executable
    const exe = b.addExecutable(.{
        .name = "cardinal",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link the pre-built FastDDS wrapper library
    exe.addLibraryPath(.{ .cwd_relative = "../build" });
    exe.linkSystemLibrary("cardinal-fastdds");
    exe.addIncludePath(.{ .cwd_relative = "../lib" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
    exe.addLibraryPath(.{ .cwd_relative = "/usr/lib/gcc/aarch64-linux-gnu/11" });
    exe.linkSystemLibrary("stdc++");
    exe.linkSystemLibrary("fastdds");
    exe.linkSystemLibrary("fastcdr");
    exe.addObjectFile(.{ .cwd_relative = "/usr/lib/gcc/aarch64-linux-gnu/11/libstdc++.a" });

    // Add to build outputs
    b.installArtifact(exe);

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
