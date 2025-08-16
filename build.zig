const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });

    // Build Fast-CDR first (dependency for FastDDS)
    const fastcdr_lib = b.addStaticLibrary(.{
        .name = "fastcdr",
        .target = target,
        .optimize = optimize,
    });

    // Add Fast-CDR source files
    const fastcdr_sources = [_][]const u8{
        "Fast-CDR/src/cpp/exceptions/BadParamException.cpp",
        "Fast-CDR/src/cpp/exceptions/NotEnoughMemoryException.cpp",
        "Fast-CDR/src/cpp/FastBuffer.cpp",
        "Fast-CDR/src/cpp/Cdr.cpp",
        "Fast-CDR/src/cpp/FastCdr.cpp",
    };

    for (fastcdr_sources) |src| {
        fastcdr_lib.addCSourceFile(.{
            .file = b.path(src),
            .flags = &[_][]const u8{
                "-std=c++17",
                "-fPIC",
                "-IFast-CDR/include",
                "-DFASTCDR_DYN_LINK",
            },
        });
    }

    fastcdr_lib.linkSystemLibrary("stdc++");
    fastcdr_lib.addIncludePath(b.path("Fast-CDR/include"));

    // Build FastDDS
    const fastdds_lib = b.addStaticLibrary(.{
        .name = "fastdds",
        .target = target,
        .optimize = optimize,
    });

    // Key FastDDS source files (simplified subset for our use case)
    const fastdds_sources = [_][]const u8{
        "Fast-DDS/src/cpp/fastdds/domain/DomainParticipantFactory.cpp",
        "Fast-DDS/src/cpp/fastdds/domain/DomainParticipant.cpp",
        "Fast-DDS/src/cpp/fastdds/publisher/Publisher.cpp",
        "Fast-DDS/src/cpp/fastdds/publisher/DataWriter.cpp",
        "Fast-DDS/src/cpp/fastdds/subscriber/Subscriber.cpp",
        "Fast-DDS/src/cpp/fastdds/subscriber/DataReader.cpp",
        "Fast-DDS/src/cpp/fastdds/topic/Topic.cpp",
        "Fast-DDS/src/cpp/fastdds/topic/TypeSupport.cpp",
        "Fast-DDS/src/cpp/rtps/participant/RTPSParticipant.cpp",
        "Fast-DDS/src/cpp/rtps/RTPSDomain.cpp",
    };

    for (fastdds_sources) |src| {
        fastdds_lib.addCSourceFile(.{
            .file = b.path(src),
            .flags = &[_][]const u8{
                "-std=c++17",
                "-fPIC",
                "-IFast-DDS/include",
                "-IFast-CDR/include",
                "-DFASTDDS_DYN_LINK",
                "-DFASTCDR_DYN_LINK",
            },
        });
    }

    fastdds_lib.linkSystemLibrary("stdc++");
    fastdds_lib.addIncludePath(b.path("Fast-DDS/include"));
    fastdds_lib.addIncludePath(b.path("Fast-CDR/include"));

    // Build Cardinal FastDDS C++ wrapper library
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
            "-IFast-DDS/include",
            "-IFast-CDR/include",
            "-Iinstall/include",
        },
    });

    cardinal_lib.linkSystemLibrary("stdc++");
    cardinal_lib.addIncludePath(b.path("lib"));
    cardinal_lib.addIncludePath(b.path("Fast-DDS/include"));
    cardinal_lib.addIncludePath(b.path("Fast-CDR/include"));

    // Install all libraries to our local install directory
    const install_step = b.addInstallArtifact(fastcdr_lib, .{
        .dest_dir = .{ .override = .{ .custom = "install/lib" } },
    });

    const install_fastdds = b.addInstallArtifact(fastdds_lib, .{
        .dest_dir = .{ .override = .{ .custom = "install/lib" } },
    });

    const install_cardinal = b.addInstallArtifact(cardinal_lib, .{
        .dest_dir = .{ .override = .{ .custom = "install/lib" } },
    });

    // Build steps
    const fastcdr_step = b.step("fastcdr", "Build Fast-CDR library");
    fastcdr_step.dependOn(&install_step.step);

    const fastdds_step = b.step("fastdds", "Build FastDDS library");
    fastdds_step.dependOn(&install_fastdds.step);
    fastdds_step.dependOn(fastcdr_step);

    const lib_step = b.step("lib", "Build all Cardinal FastDDS libraries");
    lib_step.dependOn(&install_cardinal.step);
    lib_step.dependOn(fastdds_step);

    // Default step
    const install_all = b.step("install", "Install all libraries");
    install_all.dependOn(lib_step);

    b.default_step = install_all;

    // Copy headers to install directory
    const copy_fastcdr_headers = b.addSystemCommand(&[_][]const u8{ "cp", "-r", "Fast-CDR/include/fastcdr", "install/include/" });

    const copy_fastdds_headers = b.addSystemCommand(&[_][]const u8{ "cp", "-r", "Fast-DDS/include/fastdds", "install/include/" });

    const copy_cardinal_headers = b.addSystemCommand(&[_][]const u8{ "cp", "lib/fastdds.h", "install/include/" });

    // Header copy step
    const headers_step = b.step("headers", "Copy headers to install directory");
    headers_step.dependOn(&copy_fastcdr_headers.step);
    headers_step.dependOn(&copy_fastdds_headers.step);
    headers_step.dependOn(&copy_cardinal_headers.step);

    // Make sure headers are copied when building libraries
    lib_step.dependOn(headers_step);
}
