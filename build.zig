const std = @import("std");

pub fn build(b: *std.Build) !void {
    const exe = b.addExecutable(.{
        .name = "zip",
        .optimize = b.standardOptimizeOption(.{}),
        .root_source_file = b.path("src/main.zig"),
        .target = b.standardTargetOptions(.{}),
    });

    b.installArtifact(exe);
}
