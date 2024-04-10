const std = @import("std");

pub fn build(b: *std.Build) !void {
    const exe = b.addExecutable(.{
        .name = "zip",
        .root_source_file = .{ .path = "src/main.zig" },
    });

    b.installArtifact(exe);
}
