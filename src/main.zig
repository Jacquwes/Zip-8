const std = @import("std");
const Zip = @import("zip.zig");

pub fn main() !void {
    const zip = Zip.Zip.init();
    _ = zip;
}
