const std = @import("std");
const Zip = @import("zip.zig");

pub fn main() !void {
    var GPA = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = GPA.allocator();
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    const zip_filename = args.next() orelse unreachable;

    const file_name = args.next() orelse
        return std.debug.print("Usage: {s} [file]\n", .{zip_filename});

    const file = try std.fs.cwd().openFile(file_name, .{});
    defer file.close();

    const program = try file.readToEndAlloc(allocator, 0x1000 - 0x200);

    var zip = Zip.Zip.init();

    zip.loadProgram(program);

    const result = try zip.run();
    _ = result;
}
