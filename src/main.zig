const std = @import("std");
const Zip = @import("zip.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    const exe_name = args.next() orelse unreachable;

    const rom_path = args.next() orelse
        return std.debug.print("Usage: {s} [file]\n", .{exe_name});

    const file = try std.fs.cwd().openFile(rom_path, .{});
    defer file.close();

    const rom = try file.readToEndAlloc(allocator, 0x1000 - 0x200);

    var zip = Zip.Zip.init();

    zip.loadProgram(rom);

    const result = try zip.run();
    _ = result;
}
