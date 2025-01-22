//! This module contains the code for the chip-8.

const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");
const Chip8 = @import("Chip8.zig");
const Zip = @This();

// |----------------------------| FPS: %d
// |                            | Run/Pause Step
// |                            | v1 %x   v8 %x
// |                            | v2 %x   v9 %x
// |                            | ...     ...
// |----------------------------|
// I: %x DT: %d ST: %d
// PC: %d Next: %x Inject: %x
// SP: %d Stack: >%d:%x
//
// > = dropdown

const layout = struct {
    // Display constants
    const window_width = screen_width + controls_right_size;
    const window_height = screen_height + controls_bottom_size;
    const pixel_size = 10;
    const screen_width = Chip8.screen_width * pixel_size;
    const screen_height = Chip8.screen_height * pixel_size;

    // UI constants
    const controls_right_offset_x = screen_width + controls_gap;
    const controls_right_offset_y = controls_gap;
    const controls_right_size = 200;
    const controls_bottom_offset_x = controls_gap;
    const controls_bottom_offset_y = screen_height + controls_gap;
    const controls_bottom_size = value_box_height * 3 + controls_gap * 4;
    const controls_gap = 5;
    const button_width = 70;
    const button_height = 30;
    const value_box_width = 55;
    const value_box_height = 20;
    const text_size = 20;

    // Layout constants
    const stack_pointer_x = controls_right_offset_x + value_box_label_offset;
    const stack_pointer_y = controls_bottom_offset_y + value_box_height + controls_gap;
    const inject_value_x = inject_button_x + value_box_width + controls_gap + value_box_label_offset;
    const inject_value_y = address_register_y + value_box_height + controls_gap;
    const inject_button_x = next_opcode_x + value_box_width + controls_gap;
    const inject_button_y = address_register_y + value_box_height + controls_gap;
    const next_opcode_x = program_counter_x + 10 + value_box_width + controls_gap + value_box_label_offset;
    const next_opcode_y = address_register_y + value_box_height + controls_gap;
    const program_counter_x = controls_bottom_offset_x + value_box_width;
    const program_counter_y = address_register_y + value_box_height + controls_gap;
    const sound_timer_x = delay_timer_x + value_box_width + controls_gap + value_box_label_offset;
    const sound_timer_y = controls_bottom_offset_y;
    const delay_timer_x = address_register_x + value_box_width + controls_gap + value_box_label_offset;
    const delay_timer_y = controls_bottom_offset_y;
    const address_register_x = controls_bottom_offset_x + value_box_label_offset;
    const address_register_y = controls_bottom_offset_y;
    const register_column_width = 90;
    const register_row_height = 25;
    const register_start_y = text_size + button_height + controls_gap * 3;
    const value_box_label_offset = 40;
    const registers_per_column = 8;
};

const target_fps = 60;

pub const ExecutionState = enum {
    Running,
    Paused,
};

/// Contains all the data and functions for the Zip.
chip8: Chip8,

/// The current state of the Zip.
execution_state: ExecutionState,

current_error: ?Chip8.Chip8Error,

/// The number of cycles to execute per frame
cycles_per_frame: u32,

pub fn init() Zip {
    rl.initWindow(layout.window_width, layout.window_height, "Zip");
    rl.setTargetFPS(target_fps);

    const self = Zip{
        .chip8 = Chip8.init(),
        .execution_state = .Paused,
        .cycles_per_frame = 10,
        .current_error = null,
    };
    return self;
}

/// This function runs the Zip. It will execute the instructions at the
/// program counter until an error is encountered. The function executes
/// instructions at a rate of 60Hz.
pub fn run(self: *Zip) !bool {
    var registers_editable: [Chip8.register_count]bool = [_]bool{false} ** Chip8.register_count;

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.dark_gray);
        rg.guiSetStyle(
            .default,
            rg.GuiDefaultProperty.text_size,
            layout.text_size,
        );

        if (self.current_error) |err| {
            handleError(err);
            continue;
        }

        if (self.execution_state == .Running) {
            for (0..self.cycles_per_frame) |_| {
                const opcode = self.chip8.fetchOpcode();
                self.chip8.executeNextCycle() catch |err| {
                    self.current_error = err;
                };
                // Wait for vblank after drawing a sprite
                if (opcode & 0xf000 == 0xd000) {
                    break;
                }
            }
        } else if (rg.guiButton(.{
            .height = layout.button_height,
            .width = layout.button_width,
            .x = layout.controls_right_offset_x + layout.button_width + layout.controls_gap,
            .y = layout.text_size + layout.controls_gap * 2,
        }, "Step") != 0) {
            self.chip8.executeNextCycle() catch |err| {
                self.current_error = err;
            };
        }

        if (self.chip8.delay_timer > 0)
            self.chip8.delay_timer -= 1;
        if (self.chip8.sound_timer > 0)
            self.chip8.sound_timer -= 1;

        self.updateScreen();
        try self.updateDebugInterface(&registers_editable);

        rl.drawText(
            rl.textFormat("FPS: %d", .{rl.getFPS()}),
            layout.controls_right_offset_x,
            layout.controls_gap,
            layout.text_size,
            rl.Color.light_gray,
        );
        if (rg.guiButton(.{
            .height = layout.button_height,
            .width = layout.button_width,
            .x = layout.controls_right_offset_x,
            .y = layout.text_size + layout.controls_gap * 2,
        }, if (self.execution_state == .Running) "Pause" else "Run") != 0) {
            self.execution_state = if (self.execution_state == .Running) .Paused else .Running;
        }
    }

    return true;
}

pub fn handleError(err: Chip8.Chip8Error) void {
    const result = rg.guiMessageBox(.{
        .height = 200,
        .width = 500,
        .x = 100,
        .y = 100,
    }, "An error has occurred", switch (err) {
        error.StackFull => "The call stack is full! Cannot call another function.\n",
        error.UnknownOp => "An unknown opcode has been encountered!\n",
        error.IllegalReturn => "Trying to return from global scope!\n",
        error.IllegalAddress => "Trying to access illegal address!\n",
    }, "Quit");

    if (result == 1) {
        rl.closeWindow();
        std.process.exit(0);
    }
}

pub fn updateScreen(self: *Zip) void {
    const chip8 = self.chip8;
    const screen = chip8.screen;

    rl.drawRectangle(
        0,
        0,
        layout.screen_width,
        layout.screen_height,
        rl.Color.black,
    );

    for (screen, 0..) |pixel, i| {
        const x_offset = @as(i32, @intCast(i % Chip8.screen_width)) * layout.pixel_size;
        const y_offset = @as(i32, @intCast(i / Chip8.screen_width)) * layout.pixel_size;

        if (pixel == 1) {
            rl.drawRectangle(
                x_offset,
                y_offset,
                layout.pixel_size,
                layout.pixel_size,
                rl.Color.light_gray,
            );
        }
    }
}

var inject_value: i32 = 0;
pub fn updateDebugInterface(self: *Zip, registers_editable: *[Chip8.register_count]bool) !void {
    for (&self.chip8.registers, registers_editable, 0..) |*register, *register_editable, i| {
        var value: i32 = @intCast(register.*);
        if (rg.guiValueBox(
            .{
                .height = layout.value_box_height,
                .width = layout.value_box_width,
                .x = layout.controls_right_offset_x + layout.value_box_label_offset + layout.register_column_width * @as(f32, @floatFromInt(i / layout.registers_per_column)),
                .y = layout.register_start_y + @as(f32, @floatFromInt(i % layout.registers_per_column)) * layout.register_row_height,
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

    var address_register_value: i32 = @intCast(self.chip8.address_register);
    _ = rg.guiValueBox(.{
        .height = layout.value_box_height,
        .width = layout.value_box_width,
        .x = layout.address_register_x,
        .y = layout.address_register_y,
    }, "I ", &address_register_value, 0, 0xfff, false);
    self.chip8.address_register = @truncate(@as(u32, @intCast(address_register_value)));

    var delay_timer_value: i32 = @intCast(self.chip8.delay_timer);
    _ = rg.guiValueBox(.{
        .height = layout.value_box_height,
        .width = layout.value_box_width,
        .x = layout.delay_timer_x,
        .y = layout.delay_timer_y,
    }, "DT ", &delay_timer_value, 0, 0xff, false);
    self.chip8.delay_timer = @truncate(@as(u32, @intCast(delay_timer_value)));

    var sound_timer_value: i32 = @intCast(self.chip8.sound_timer);
    _ = rg.guiValueBox(.{
        .height = layout.value_box_height,
        .width = layout.value_box_width,
        .x = layout.sound_timer_x,
        .y = layout.sound_timer_y,
    }, "ST ", &sound_timer_value, 0, 0xff, false);
    self.chip8.sound_timer = @truncate(@as(u32, @intCast(sound_timer_value)));

    var pc_value: i32 = @intCast(self.chip8.program_counter);
    _ = rg.guiValueBox(.{
        .height = layout.value_box_height,
        .width = layout.value_box_width,
        .x = layout.program_counter_x,
        .y = layout.program_counter_y,
    }, "PC ", &pc_value, 0, 0xfff, false);
    self.chip8.program_counter = @truncate(@as(u32, @intCast(pc_value)));

    var next_value: i32 = @intCast(std.mem.readInt(
        u16,
        self.chip8.memory[self.chip8.program_counter .. self.chip8.program_counter + 2][0..2],
        .big,
    ));
    _ = rg.guiValueBox(.{
        .height = layout.value_box_height,
        .width = layout.value_box_width,
        .x = layout.next_opcode_x,
        .y = layout.next_opcode_y,
    }, "Next ", &next_value, 0, 0xffff, false);

    _ = rg.guiValueBox(.{
        .height = layout.value_box_height,
        .width = layout.value_box_width,
        .x = layout.inject_value_x,
        .y = layout.inject_value_y,
    }, "", &inject_value, 0, 0xffff, false);

    if (rg.guiButton(.{
        .height = layout.button_height,
        .width = layout.button_width,
        .x = layout.inject_button_x,
        .y = layout.inject_button_y,
    }, "Inject") != 0) {
        try self.chip8.executeOpcode(@truncate(@as(u32, @intCast(inject_value))));
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
