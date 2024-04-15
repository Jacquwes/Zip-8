const std = @import("std");
const Zip = @import("zip.zig");

pub fn main() !void {
    var zip = Zip.Zip.init();
    const result = try zip.run();
    _ = result;
}
