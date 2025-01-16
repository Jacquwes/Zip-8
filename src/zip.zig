//! This module contains the code for the chip-8.

const std = @import("std");
const rl = @import("raylib");

/// The error type for the Zip.
pub const ZipError = error{
    IllegalAddress,
    IllegalReturn,
    StackFull,
    UnknownOp,
};

const screen_width = 640;
const screen_height = 320;

/// Contains all the data and functions for the Zip.
pub const Zip = struct {
    /// 4096 bytes of memory.
    memory: [0x1000]u8,
    /// 16 general purpose registers.
    registers: [0x10]u8,

    /// This register is used to store memory addresses used by the running
    /// program.
    address_register: u12,
    /// This register stores the currently executing instruction address.
    program_counter: u16,

    /// The stack stores the address that the program should return to after
    /// a subroutine call.
    stack: [0x60]u12,
    /// The stack pointer points to the top of the stack.
    stack_ptr: u8,

    /// The delay timer is decremented at a rate of 60Hz.
    delay_timer: u8,
    /// The sound timer is decremented at a rate of 60Hz.
    sound_timer: u8,

    /// The screen buffer. It is 64x32 pixels.
    screen: [0x20 * 0x40]u1,

    /// Address of the sprites in memory.
    const sprites_address: u12 = 0;
    /// The sprites for the chip-8.
    const sprites = [0x10][5]u8{
        [_]u8{ 0xf0, 0x90, 0x90, 0x90, 0xf0 }, // 0
        [_]u8{ 0x20, 0x60, 0x20, 0x20, 0x70 }, // 1
        [_]u8{ 0x20, 0x10, 0xf0, 0x80, 0xf0 }, // 2
        [_]u8{ 0xf0, 0x10, 0xf0, 0x10, 0xf0 }, // 3
        [_]u8{ 0x90, 0x90, 0xf0, 0x10, 0x10 }, // 4
        [_]u8{ 0xf0, 0x80, 0xf0, 0x10, 0xf0 }, // 5
        [_]u8{ 0xf0, 0x80, 0xf0, 0x90, 0xf0 }, // 6
        [_]u8{ 0xf0, 0x10, 0x20, 0x40, 0x40 }, // 7
        [_]u8{ 0xf0, 0x90, 0xf0, 0x90, 0xf0 }, // 8
        [_]u8{ 0xf0, 0x90, 0xf0, 0x10, 0xf0 }, // 9
        [_]u8{ 0xf0, 0x90, 0xf0, 0x90, 0x90 }, // A
        [_]u8{ 0xe0, 0x90, 0xe0, 0x90, 0xe0 }, // B
        [_]u8{ 0xf0, 0x80, 0x80, 0x80, 0xf0 }, // C
        [_]u8{ 0xe0, 0x90, 0x90, 0x90, 0xe0 }, // D
        [_]u8{ 0xf0, 0x80, 0xf0, 0x80, 0xf0 }, // E
        [_]u8{ 0xf0, 0x80, 0xf0, 0x80, 0x80 }, // F
    };

    /// Initializes the registers and copies the sprites to memory.
    /// Also initializes raylib.
    pub fn init() Zip {
        rl.initWindow(screen_width, screen_height, "Zip-8");
        rl.setTargetFPS(60);

        var zip: Zip = .{
            .address_register = 0,
            .delay_timer = 0,
            .memory = [_]u8{0} ** 0x1000,
            .program_counter = 0,
            .registers = [_]u8{0} ** 0x10,
            .screen = [_]u1{0} ** (0x20 * 0x40),
            .sound_timer = 0,
            .stack = [_]u12{0} ** 0x60,
            .stack_ptr = 0,
        };

        for (sprites, 0..) |sprite, i| {
            @memcpy(zip.memory[i * 5 .. i * 5 + 5], &sprite);
        }

        return zip;
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
                self.tick() catch |err| switch (err) {
                    ZipError.StackFull => break :zip_loop try stdout.print(
                        "The call stack is full! Cannot call another function.\n",
                        .{},
                    ),
                    ZipError.UnknownOp => break :zip_loop try stdout.print(
                        "An unknown opcode has been encountered!\n",
                        .{},
                    ),
                    ZipError.IllegalReturn => break :zip_loop try stdout.print(
                        "Trying to return from global scope!\n",
                        .{},
                    ),
                    ZipError.IllegalAddress => break :zip_loop try stdout.print(
                        "Trying to access illegal address!\n",
                        .{},
                    ),
                };
            }
        }

        return true;
    }

    /// Load program bytes into the Zip memory starting at address 0x200.
    pub fn loadProgram(self: *Zip, program: []const u8) void {
        @memcpy(self.memory[0x200 .. 0x200 + program.len], program);
    }

    /// Print the current state of the Zip components.
    pub fn printState(self: *const Zip) !void {
        const stdout = std.io.getStdOut().writer();

        try stdout.print("Registers:\n", .{});
        for (self.registers, 0..) |register, i| {
            try stdout.print("\tV{d}: {d}\n", .{ i, register });
        }
        try stdout.print("Address Register: {d}\n", .{self.address_register});
        try stdout.print("Program Counter: {d}\n", .{self.program_counter});
        try stdout.print("Stack Pointer: {d}\n", .{self.stack_ptr});
        try stdout.print("Stack:\n", .{});
        for (self.stack, 0..) |address, i| {
            if (address != 0)
                try stdout.print("\t{d}: {d}\n", .{ i, address });
        }
        try stdout.print("Delay Timer: {d}\n", .{self.delay_timer});
        try stdout.print("Sound Timer: {d}\n", .{self.sound_timer});
        try stdout.print("Current Instruction: {x}\n", .{self.memory[self.program_counter .. self.program_counter + 2]});
    }

    /// This function executes the next instruction at the program counter.
    /// It will increment the program counter by 2, decrement the delay and
    /// sound timers by 1, and execute the instruction.
    fn tick(self: *Zip) !void {
        const instruction: u16 = std.mem.readInt(
            u16,
            self.memory[self.program_counter .. self.program_counter + 2][0..2],
            .little,
        );

        try self.executeInstruction(instruction);

        self.program_counter += 2;
        self.delay_timer -= 1;
        self.sound_timer -= 1;
    }

    /// This function executes the given instruction.
    fn executeInstruction(self: *Zip, instruction: u16) !void {
        return switch (instruction & 0xf000) {
            0x0000 => switch (instruction) {
                0x00e0 => self.clearScreen(),
                0x0ee0 => self.returnFromSubroutine(),
                else => ZipError.UnknownOp,
            },
            0x1000 => self.gotoAddress(@truncate(instruction)),
            0x2000 => self.callSubroutine(@truncate(instruction)),
            0x3000 => self.skipEqual(@truncate(instruction >> 8), @truncate(instruction)),
            0x4000 => self.skipNotEqual(@truncate(instruction >> 8), @truncate(instruction)),
            0x5000 => switch (instruction & 0x000f) {
                0 => self.skipRegistersEqual(@truncate(instruction >> 8), @truncate(instruction >> 4)),
                else => ZipError.UnknownOp,
            },
            0x6000 => self.setRegisterToValue(@truncate(instruction >> 8), @truncate(instruction)),
            0x7000 => self.registerAddValue(@truncate(instruction >> 8), @truncate(instruction)),
            0x8000 => switch (instruction & 0x000f) {
                0 => self.setRegisterToRegister(@truncate(instruction >> 8), @truncate(instruction >> 4)),
                1 => self.registerOrRegister(@truncate(instruction >> 8), @truncate(instruction >> 4)),
                2 => self.registerAndRegister(@truncate(instruction >> 8), @truncate(instruction >> 4)),
                3 => self.registerXorRegister(@truncate(instruction >> 8), @truncate(instruction >> 4)),
                4 => self.registerPlusRegister(@truncate(instruction >> 8), @truncate(instruction >> 4)),
                5 => self.registerMinusRegister(@truncate(instruction >> 8), @truncate(instruction >> 4)),
                6 => self.registerShiftRight(@truncate(instruction >> 8), @truncate(instruction >> 4)),
                7 => self.registerRegisterMinus(@truncate(instruction >> 8), @truncate(instruction >> 4)),
                14 => self.registerShiftLeft(@truncate(instruction >> 8), @truncate(instruction >> 4)),
                else => ZipError.UnknownOp,
            },
            0x9000 => self.skipRegistersNotEqual(@truncate(instruction >> 8), @truncate(instruction >> 4)),
            0xa000 => self.loadAddress(@truncate(instruction)),
            0xb000 => self.gotoAddressV0(@truncate(instruction)),
            0xc000 => self.setRegisterToRandomAndN(@truncate(instruction >> 8), @truncate(instruction)),
            0xd000 => self.drawSprite(@truncate(instruction >> 8), @truncate(instruction >> 4), @truncate(instruction)),
            0xe000 => switch ((instruction & 0x00ff)) {
                0x9e => self.skipIfKeyPressed(@truncate(instruction >> 8)),
                0xa1 => self.skipIfKeyNotPressed(@truncate(instruction >> 8)),
                else => ZipError.UnknownOp,
            },
            0xf000 => switch (instruction & 0x00ff) {
                0x07 => self.getDelay(@truncate(instruction >> 8)),
                0x0a => self.getKey(@truncate(instruction >> 8)),
                0x15 => self.setDelayTimer(@truncate(instruction >> 8)),
                0x18 => self.setSoundTimer(@truncate(instruction >> 8)),
                0x1e => self.addRegisterToAddress(@truncate(instruction >> 8)),
                0x29 => self.setAddressToSprite(@truncate(instruction >> 8)),
                0x33 => self.storeBinaryCodedRegister(@truncate(instruction >> 8)),
                0x55 => self.dumpRegistersUpTo(@truncate(instruction >> 8)),
                0x65 => self.loadRegistersUpTo(@truncate(instruction >> 8)),
                else => ZipError.UnknownOp,
            },
            else => ZipError.UnknownOp,
        };
    }

    /// FX1E - Adds the value of the register X to the address register.
    fn addRegisterToAddress(self: *Zip, register: u4) void {
        self.address_register += self.registers[register];
    }

    /// 2NNN - Calls a subroutine at the given address. The address is pushed onto
    /// the stack and the stack pointer is incremented. If the stack is full,
    /// it will return an error.
    fn callSubroutine(self: *Zip, address: u12) ZipError!void {
        if (self.stack_ptr == 0x5f) return ZipError.StackFull;

        self.stack[self.stack_ptr] = address;
        self.stack_ptr += 1;
    }

    /// 00E0 - Clears the screen buffer.
    fn clearScreen(self: *Zip) void {
        self.screen = [_]u1{0} ** (0x20 * 0x40);
    }

    /// DXYN - Draws the sprite at the address stored in the address register
    /// at the given coordinates. The sprite is 8 pixels wide and N pixels
    /// tall. The sprite is XORed with the screen buffer. If a pixel is
    /// erased, the carry flag is set to 1.
    fn drawSprite(self: *Zip, x: u4, y: u4, height: u4) void {
        var iY: u8 = 0;
        while (iY < height) : (iY += 1) {
            var iX: u8 = 0;
            while (iX < 8) : (iX += 1) {
                const currentSpritePixel = (self.memory[self.address_register + iY] >> (7 - @as(u3, @intCast(iX)))) & 1;
                const currentScreenPixel = (self.screen[(y + iY) * 0x40 + (x + iX)]) & 1;

                if (currentSpritePixel == 1 and currentScreenPixel == 1) {
                    self.registers[0xf] = 1;
                    self.screen[(y + iY) * 0x40 + (x + iX)] = 0;
                } else {
                    self.screen[(y + iY) * 0x40 + (x + iX)] = 1;
                }
            }
        }
    }

    /// FX55 - Dumps the values of the registers up to register X into memory
    /// starting at the address stored in the address register.
    fn dumpRegistersUpTo(self: *Zip, register: u4) void {
        for (self.registers, 0..register) |value, i| {
            self.memory[i + self.address_register] = value;
        }
    }

    /// FX07 - Set the value of register X to the value of the delay timer.
    fn getDelay(self: *Zip, register: u4) void {
        self.registers[register] = self.delay_timer;
    }

    /// FX0A - Wait for a key press and store the value in register X.
    fn getKey(self: *Zip, register: u4) !void {
        _ = register;
        _ = self;
    }

    /// 1NNN - Jump to the address NNN without saving the current address.
    fn gotoAddress(self: *Zip, address: u12) void {
        self.program_counter = address;
    }

    /// BNNN - Jump to the address NNN plus the value in register 0.
    fn gotoAddressV0(self: *Zip, address: u12) void {
        self.program_counter = address + self.registers[0];
    }

    /// ANNN - Set the address register to NNN.
    fn loadAddress(self: *Zip, address: u12) void {
        self.address_register = address;
    }

    /// FX65 - Load X bytes from the memory starting at the address stored in
    /// the address register into the registers up to register X.
    fn loadRegistersUpTo(self: *Zip, register: u4) void {
        for (0..register) |i| {
            self.registers[i] = self.memory[self.address_register + i];
        }
    }

    /// 8XY5 - Subtracts the value of register Y from the value of register X.
    /// If the value of register X is greater than the value of register Y, it
    /// will set the carry flag to 1.
    fn registerMinusRegister(self: *Zip, x: u4, y: u4) void {
        if (self.registers[x] >= self.registers[y])
            self.registers[0xf] = 1;

        self.registers[x] -= self.registers[y];
    }

    /// 8XY4 - Adds the value of register Y to the value of register X. If the
    /// result is greater than 255, it will set the carry flag to 1.
    fn registerPlusRegister(self: *Zip, x: u4, y: u4) void {
        const result: u16 = self.registers[x] + self.registers[y];
        if (result > 0xff)
            self.registers[0xf] = 1;

        self.registers[x] = @truncate(result);
    }

    /// 7XNN - Adds the value NN to the value in register X.
    fn registerAddValue(self: *Zip, register: u4, value: u8) void {
        const result: u8 = @truncate((self.registers[register] + value));

        self.registers[register] = result;
    }

    /// 8XY2 - Set the value of register X to the value of register X AND the
    /// value of register Y.
    fn registerAndRegister(self: *Zip, x: u4, y: u4) void {
        self.registers[x] &= self.registers[y];
    }

    /// 8XY7 - Set the value of register X to the value of register Y minus
    /// the value of register X. If the value of register Y is greater than
    /// the value of register X, it will set the carry flag to 1.
    fn registerRegisterMinus(self: *Zip, x: u4, y: u4) void {
        if (self.registers[y] >= self.registers[x])
            self.registers[0xf] = 1;

        self.registers[x] = self.registers[y] - self.registers[x];
    }

    /// 8XYE - Shifts the value of register X to the left by 1. The most
    /// significant bit is stored in the carry flag.
    fn registerShiftLeft(self: *Zip, x: u4, y: u4) void {
        _ = y;
        self.registers[0xf] = (self.registers[x] & 0b1000_0000) >> 7;

        self.registers[x] <<= 1;
    }

    /// 8XY6 - Shifts the value of register X to the right by 1. The least
    /// significant bit is stored in the carry flag.
    fn registerShiftRight(self: *Zip, x: u4, y: u4) void {
        _ = y;
        self.registers[0xf] = self.registers[x] & 0b0000_0001;
        self.registers[x] >>= 1;
    }

    /// 8XY1 - Set the value of register X to the value of register X OR the
    /// value of register Y.
    fn registerOrRegister(self: *Zip, x: u4, y: u4) void {
        self.registers[x] |= self.registers[y];
    }

    /// 8XY3 - Set the value of register X to the value of register X XOR the
    /// value of register Y.
    fn registerXorRegister(self: *Zip, x: u4, y: u4) void {
        self.registers[x] ^= self.registers[y];
    }

    /// 00EE - Returns from a subroutine. Calling this function will pop the
    /// top of the stack and set the program counter to that value. If there
    /// are no more values in the stack, it will return an error.
    fn returnFromSubroutine(self: *Zip) ZipError!void {
        if (self.stack_ptr == 0) return ZipError.IllegalReturn;

        self.program_counter = self.stack[self.stack_ptr - 1];
        self.stack_ptr -= 1;
    }

    /// FX29 - Set the address register to the address of the sprite
    /// corresponding to the value in register X.
    fn setAddressToSprite(self: *Zip, register: u4) void {
        self.address_register = sprites_address + self.registers[register];
    }

    /// FX15 - Set the delay timer to the value of register X.
    fn setDelayTimer(self: *Zip, register: u4) void {
        self.delay_timer = self.registers[register];
    }

    /// 8XY0 - Set the value of register X to the value of register Y.
    fn setRegisterToRegister(self: *Zip, x: u4, y: u4) void {
        self.registers[x] = self.registers[y];
    }

    /// 6XNN - Set the value of register X to NN.
    fn setRegisterToValue(self: *Zip, register: u4, value: u8) void {
        self.registers[register] = value;
    }

    /// CXNN - Set the value of register X to a random number AND NN.
    fn setRegisterToRandomAndN(self: *Zip, x: u4, n: u8) void {
        var random_generator = std.rand.Xoshiro256.init(0);
        const random_number = random_generator.random().int(u8);
        self.registers[x] = random_number & n;
    }

    /// FX18 - Set the sound timer to the value of register X.
    fn setSoundTimer(self: *Zip, register: u4) void {
        self.sound_timer = self.registers[register];
    }

    /// 3XNN - Skip the next instruction if the value in register X is equal to NN.
    fn skipEqual(self: *Zip, register: u4, value: u8) void {
        if (self.registers[register] == value)
            self.program_counter += 2;
    }

    /// EX9E - Skip the next instruction if the key corresponding to the value
    /// in register X is pressed.
    fn skipIfKeyPressed(self: *Zip, register: u4) void {
        _ = register;
        _ = self;
    }

    /// EXA1 - Skip the next instruction if the key corresponding to the value
    /// in register X is not pressed.
    fn skipIfKeyNotPressed(self: *Zip, register: u4) void {
        _ = register;
        _ = self;
    }

    /// 4XNN - Skip the next instruction if the value in register X is not
    /// equal to NN.
    fn skipNotEqual(self: *Zip, register: u4, value: u8) void {
        if (self.registers[register] != value)
            self.program_counter += 2;
    }

    /// 5XY0 - Skip the next instruction if the value in register X is equal
    /// to the value in register Y.
    fn skipRegistersEqual(self: *Zip, x: u4, y: u4) void {
        if (self.registers[x] == self.registers[y])
            self.program_counter += 2;
    }

    /// 9XY0 - Skip the next instruction if the value in register X is not
    /// equal to the value in register Y.
    fn skipRegistersNotEqual(self: *Zip, x: u4, y: u4) void {
        if (self.registers[x] != self.registers[y])
            self.program_counter += 2;
    }

    /// FX33 - Store the binary-coded decimal representation of the value in
    /// register X at the address stored in the address register.
    /// The hundreds digit is stored at the address, the tens digit is stored
    /// at the address + 1, and the ones digit is stored at the address + 2.
    fn storeBinaryCodedRegister(self: *Zip, x: u4) !void {
        if (self.address_register > 0x1000 - 3)
            return ZipError.IllegalAddress;

        const value = self.registers[x];
        const hundreds = value / 100;
        const tens = (value % 100) / 10;
        const ones = (value % 10);

        self.memory[self.address_register] = hundreds;
        self.memory[self.address_register + 1] = tens;
        self.memory[self.address_register + 2] = ones;
    }
};
