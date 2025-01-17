//! This module contains the code for the chip-8.

const std = @import("std");
const Chip8 = @import("Chip8.zig");
const rl = @import("raylib");

const screen_width = 640;
const screen_height = 320;

/// Contains all the data and functions for the Zip.
pub const Zip = struct {
    chip8: Chip8,

    pub fn init() Zip {
        rl.initWindow(screen_width, screen_height, "Zip");
        rl.setTargetFPS(60);

        const self = Zip{ .chip8 = Chip8.init() };
        return self;
    }

    /// This function runs the Zip. It will execute the instructions at the
    /// program counter until an error is encountered. The function executes
    /// instructions at a rate of 60Hz.
    pub fn run(self: *Zip) !bool {
        const stdout = std.io.getStdOut().writer();
        var timer = try std.time.Timer.start();

        zip_loop: while (true) {
            const elapsed_nanoseconds = timer.read();
            if (elapsed_nanoseconds * std.time.ns_per_s >
                @as(u64, @intFromFloat(1.0 / 60.0)))
            {
                self.chip8.executeNextCycle() catch |err| switch (err) {
                    .StackFull => {
                        try stdout.print(
                            "The call stack is full! Cannot call another function.\n",
                            .{},
                        );
                        try self.dumpState();
                        break :zip_loop;
                    },
                    .UnknownOp => {
                        try stdout.print(
                            "An unknown opcode has been encountered!\n",
                            .{},
                        );
                        try self.dumpState();
                        break :zip_loop;
                    },
                    .IllegalReturn => {
                        try stdout.print(
                            "Trying to return from global scope!\n",
                            .{},
                        );
                        try self.dumpState();
                        break :zip_loop;
                    },
                    .IllegalAddress => {
                        try stdout.print(
                            "Trying to access illegal address!\n",
                            .{},
                        );
                        try self.dumpState();
                        break :zip_loop;
                    },
                };

                rl.beginDrawing();
                defer rl.endDrawing();

                rl.clearBackground(rl.Color.white);
            }
        }

        return true;
    }

    /// Load program bytes into the Zip memory starting at address 0x200.
    pub fn loadProgram(self: *Zip, program: []const u8) void {
        @memcpy(self.memory[0x200 .. 0x200 + program.len], program);
    }

    /// Print the current state of the Zip components.
    pub fn dumpState(self: *const Zip) !void {
        const stdout = std.io.getStdOut().writer();
        const chip8 = self.chip8;

        try stdout.print("Registers:\n", .{});
        for (chip8.registers, 0..) |register, i| {
            try stdout.print("\tV{d}: {d}\n", .{ i, register });
        }
        try stdout.print("Address Register: {d}\n", .{chip8.address_register});
        try stdout.print("Program Counter: {d}\n", .{chip8.program_counter});
        try stdout.print("Stack Pointer: {d}\n", .{chip8.stack_ptr});
        try stdout.print("Stack:\n", .{});
        for (chip8.stack, 0..) |address, i| {
            if (address != 0)
                try stdout.print("\t{d}: {d}\n", .{ i, address });
        }
        try stdout.print("Delay Timer: {d}\n", .{chip8.delay_timer});
        try stdout.print("Sound Timer: {d}\n", .{chip8.sound_timer});
        try stdout.print("Current Instruction: {x}\n", .{chip8.memory[chip8.program_counter .. chip8.program_counter + 2]});
    }
};
