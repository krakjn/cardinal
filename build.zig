const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });

    // Build Cardinal FastDDS C++ wrapper library only
    // FastDDS and Fast-CDR are built with CMake separately
    const cardinal_lib = b.addStaticLibrary(.{
        .name = "cardinal-fastdds",
        .target = target,
        .optimize = optimize,
    });

    // Add our wrapper source file
    cardinal_lib.addCSourceFile(.{
        .file = b.path("lib/fastdds.cpp"),
        .flags = &[_][]const u8{
            "-std=c++17",
            "-fPIC",
            "-Ilib",
            "-Iinstall/include",
            "-IFast-DDS/include",
            "-IFast-CDR/include",
        },
    });

    cardinal_lib.linkSystemLibrary("stdc++");
    cardinal_lib.addIncludePath(b.path("lib"));
    cardinal_lib.addIncludePath(b.path("install/include"));
    cardinal_lib.addIncludePath(b.path("Fast-DDS/include"));
    cardinal_lib.addIncludePath(b.path("Fast-CDR/include"));

    // Install Cardinal wrapper library to build directory for Go
    const install_cardinal = b.addInstallArtifact(cardinal_lib, .{
        .dest_dir = .{ .override = .{ .custom = "build" } },
    });

    // Build steps
    const lib_step = b.step("lib", "Build Cardinal FastDDS wrapper library");
    lib_step.dependOn(&install_cardinal.step);

    // Default step
    b.default_step = lib_step;
}
