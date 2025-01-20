//! This module contains the code for the chip-8.

const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");
const Chip8 = @import("Chip8.zig");
const Zip = @This();

// Display constants
const window_width = screen_width + controls_right_size;
const window_height = screen_height;
const pixel_size = 10;
const screen_width = Chip8.screen_width * pixel_size;
const screen_height = Chip8.screen_height * pixel_size;

// UI constants
const controls_right_offset_x = screen_width + controls_gap;
const controls_right_offset_y = controls_gap;
const controls_right_size = 200;
const controls_gap = 5;
const button_width = 70;
const button_height = 30;
const value_box_width = 50;
const value_box_height = 20;
const text_size = 20;

// Layout constants
const register_column_width = 90;
const register_row_height = 25;
const register_start_y = 100;
const register_label_offset = 30;
const registers_per_column = 8;
const target_fps = 300;

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
    rl.setTargetFPS(target_fps);

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
    var registers_editable: [Chip8.register_count]bool = [_]bool{false} ** Chip8.register_count;

    zip_loop: while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.dark_gray);

        rg.guiSetStyle(
            .default,
            rg.GuiDefaultProperty.text_size,
            text_size,
        );

        // This will only draw step button if not running
        const should_execute = self.execution_state == .Running or
            rg.guiButton(.{
            .height = button_height,
            .width = button_width,
            .x = controls_right_offset_x + button_width + controls_gap,
            .y = text_size + controls_gap * 2,
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
        self.updateDebugInterface(&registers_editable);

        rl.drawText(
            rl.textFormat("FPS: %d", .{rl.getFPS()}),
            controls_right_offset_x,
            controls_gap,
            text_size,
            rl.Color.light_gray,
        );
        if (rg.guiButton(.{
            .height = button_height,
            .width = button_width,
            .x = controls_right_offset_x,
            .y = text_size + controls_gap * 2,
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
        screen_width,
        screen_height,
        rl.Color.black,
    );

    for (screen, 0..) |pixel, i| {
        const x_offset = @as(i32, @intCast(i % Chip8.screen_width)) * pixel_size;
        const y_offset = @as(i32, @intCast(i / Chip8.screen_width)) * pixel_size;

        if (pixel == 1) {
            rl.drawRectangle(
                x_offset,
                y_offset,
                pixel_size,
                pixel_size,
                rl.Color.light_gray,
            );
        }
    }
}

pub fn updateDebugInterface(self: *Zip, registers_editable: *[Chip8.register_count]bool) void {
    for (&self.chip8.registers, registers_editable, 0..) |*register, *register_editable, i| {
        var value: i32 = @intCast(register.*);
        if (rg.guiValueBox(
            .{
                .height = value_box_height,
                .width = value_box_width,
                .x = controls_right_offset_x + register_label_offset + register_column_width * @as(f32, @floatFromInt(i / registers_per_column)),
                .y = register_start_y + @as(f32, @floatFromInt(i % registers_per_column)) * register_row_height,
            },
            rl.textFormat("v%X ", .{i}),
            &value,
            0,
            255,
            self.execution_state == .Paused and register_editable.*,
        ) != 0) {
            @memset(registers_editable, false);
            register_editable.* = true;
        }
        register.* = @truncate(@as(u32, @intCast(value)));
    }
}

/// Load program bytes into the Zip memory starting at address 0x200.
pub fn loadProgram(self: *Zip, program: []const u8) void {
    @memcpy(self.chip8.memory[Chip8.reserved_mem_size .. Chip8.reserved_mem_size + program.len], program);
}

/// Print the current state of the Zip components.
pub fn dumpState(self: *const Zip) !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("Registers:\n", .{});
    for (self.chip8.registers, 0..) |register, i| {
        try stdout.print("\tV{d}: {d}\n", .{ i, register });
    }
    try stdout.print("Address Register: {d}\n", .{self.chip8.address_register});
    try stdout.print("Program Counter: {d}\n", .{self.chip8.program_counter});
    try stdout.print("Stack Pointer: {d}\n", .{self.chip8.stack_ptr});
    try stdout.print("Stack:\n", .{});
    for (self.chip8.stack, 0..) |address, i| {
        if (address != 0)
            try stdout.print("\t{d}: {d}\n", .{ i, address });
    }
    try stdout.print("Delay Timer: {d}\n", .{self.chip8.delay_timer});
    try stdout.print("Sound Timer: {d}\n", .{self.chip8.sound_timer});
    try stdout.print("Current Instruction: {x:0>4}\n", .{std.mem.readInt(
        u16,
        self.chip8.memory[self.chip8.program_counter .. self.chip8.program_counter + 2][0..2],
        .big,
    )});
}
