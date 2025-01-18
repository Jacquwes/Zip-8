//! This module contains the code for the chip-8.

const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");
const Chip8 = @import("Chip8.zig");
const Zip = @This();

const window_width = Chip8.screen_width * 10 + 200;
const window_height = Chip8.screen_height * 10;
const controls_offset = Chip8.screen_width * 10 + 5;

pub const ExecutionState = enum {
    Running,
    Paused,
};

/// Contains all the data and functions for the Zip.
chip8: Chip8,

/// The current state of the Zip.
execution_state: ExecutionState,

pub fn init() Zip {
    rl.initWindow(window_width, window_height, "Zip");
    rl.setTargetFPS(300);

    const self = Zip{
        .chip8 = Chip8.init(),
        .execution_state = .Paused,
    };
    return self;
}

/// This function runs the Zip. It will execute the instructions at the
/// program counter until an error is encountered. The function executes
/// instructions at a rate of 60Hz.
pub fn run(self: *Zip) !bool {
    zip_loop: while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.dark_gray);

        rg.guiSetStyle(
            .default,
            rg.GuiDefaultProperty.text_size,
            20,
        );

        // This will only draw step button if not running
        const should_execute = self.execution_state == .Running or
            rg.guiButton(.{
            .height = 40,
            .width = 70,
            .x = controls_offset + 80,
            .y = 30,
        }, "Step") != 0;

        if (should_execute) {
            self.chip8.executeNextCycle() catch |err| switch (err) {
                error.StackFull => {
                    std.debug.print("The call stack is full! Cannot call another function.\n", .{});
                    try self.dumpState();
                    break :zip_loop;
                },
                error.UnknownOp => {
                    std.debug.print("An unknown opcode has been encountered!\n", .{});
                    try self.dumpState();
                    break :zip_loop;
                },
                error.IllegalReturn => {
                    std.debug.print("Trying to return from global scope!\n", .{});
                    try self.dumpState();
                    break :zip_loop;
                },
                error.IllegalAddress => {
                    std.debug.print("Trying to access illegal address!\n", .{});
                    try self.dumpState();
                    break :zip_loop;
                },
            };
        }

        self.updateScreen();

        rl.drawText(
            rl.textFormat("FPS: %d", .{rl.getFPS()}),
            controls_offset,
            5,
            20,
            rl.Color.light_gray,
        );
        if (rg.guiButton(.{
            .height = 40,
            .width = 70,
            .x = controls_offset,
            .y = 30,
        }, if (self.execution_state == .Running) "Pause" else "Run") != 0) {
            self.execution_state = if (self.execution_state == .Running) .Paused else .Running;
        }
    }

    return true;
}

pub fn updateScreen(self: *Zip) void {
    const chip8 = self.chip8;
    const screen = chip8.screen;

    rl.drawRectangle(
        0,
        0,
        Chip8.screen_width * 10,
        Chip8.screen_height * 10,
        rl.Color.black,
    );

    for (screen, 0..) |pixel, i| {
        const x_offset = @as(i32, @intCast(i % Chip8.screen_width)) * 10;
        const y_offset = @as(i32, @intCast(i / Chip8.screen_width)) * 10;

        if (pixel == 1) {
            rl.drawRectangle(
                x_offset,
                y_offset,
                10,
                10,
                rl.Color.light_gray,
            );
        }
    }
}

/// Load program bytes into the Zip memory starting at address 0x200.
pub fn loadProgram(self: *Zip, program: []const u8) void {
    @memcpy(self.chip8.memory[0x200 .. 0x200 + program.len], program);
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
    try stdout.print("Current Instruction: {x:0>4}\n", .{std.mem.readInt(
        u16,
        self.chip8.memory[self.chip8.program_counter .. self.chip8.program_counter + 2][0..2],
        .big,
    )});
}
