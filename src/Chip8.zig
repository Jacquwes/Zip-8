//! The Chip-8 virtual machine.

const std = @import("std");
const rl = @import("raylib");
const Chip8 = @This();

/// The error type for the Chip-8.
pub const Chip8Error = error{
    IllegalAddress,
    IllegalReturn,
    StackFull,
    UnknownOp,
};

pub const memory_size = 0x1000;
pub const register_count = 0x10;
pub const reserved_mem_size = 0x200;
pub const screen_width = 0x40;
pub const screen_height = 0x20;
pub const sprites_address = 0;
pub const stack_size = 0x60;

/// 4096 bytes of memory.
memory: [memory_size]u8,
/// 16 general purpose registers.
registers: [register_count]u8,

/// This register is used to store memory addresses used by the running
/// program.
address_register: u12,
/// This register stores the currently executing opcode address.
program_counter: u16,

/// The stack stores the address that the program should return to after
/// a subroutine call.
stack: [stack_size]u12,
/// The stack pointer points to the top of the stack.
stack_ptr: u8,

/// The delay timer is decremented at a rate of 60Hz.
delay_timer: u8,
/// The sound timer is decremented at a rate of 60Hz.
sound_timer: u8,

/// The screen buffer. It is 64x32 pixels.
screen: [screen_height * screen_width]u1,

/// Whether the program is waiting for a key press.
waiting_for_key: ?u4 = null,

/// Whether the last opcode was a branch instruction.
branching: bool = false,

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
pub fn init() Chip8 {
    var chip8: Chip8 = .{
        .address_register = 0,
        .delay_timer = 0,
        .memory = [_]u8{0} ** memory_size,
        .program_counter = reserved_mem_size,
        .registers = [_]u8{0} ** register_count,
        .screen = [_]u1{0} ** (screen_height * screen_width),
        .sound_timer = 0,
        .stack = [_]u12{0} ** stack_size,
        .stack_ptr = 0,
    };

    for (sprites, 0..) |sprite, i| {
        @memcpy(chip8.memory[i * 5 .. i * 5 + 5], &sprite);
    }

    return chip8;
}

/// This function fetches the next opcode at the program counter.
pub fn fetchOpcode(self: *const Chip8) u16 {
    return std.mem.readInt(
        u16,
        self.memory[self.program_counter .. self.program_counter + 2][0..2],
        .big,
    );
}

/// This function executes the next opcode at the program counter.
/// It will increment the program counter by 2, decrement the delay and
/// sound timers by 1, and execute the opcode.
pub fn executeNextCycle(self: *Chip8) Chip8Error!void {
    const opcode = self.fetchOpcode();

    if (self.waiting_for_key) |register|
        return self.getKey(register);

    try self.executeOpcode(opcode);

    if (!self.branching) self.program_counter += 2;
    self.branching = false;
}

/// This function executes the given opcode.
pub fn executeOpcode(self: *Chip8, opcode: u16) Chip8Error!void {
    return switch (opcode & 0xf000) {
        0x0000 => switch (opcode) {
            0x00e0 => self.clearScreen(),
            0x00ee => self.returnFromSubroutine(),
            else => Chip8Error.UnknownOp,
        },
        0x1000 => self.gotoAddress(@truncate(opcode)),
        0x2000 => self.callSubroutine(@truncate(opcode)),
        0x3000 => self.skipEqual(@truncate(opcode >> 8), @truncate(opcode)),
        0x4000 => self.skipNotEqual(@truncate(opcode >> 8), @truncate(opcode)),
        0x5000 => switch (opcode & 0x000f) {
            0 => self.skipRegistersEqual(@truncate(opcode >> 8), @truncate(opcode >> 4)),
            else => Chip8Error.UnknownOp,
        },
        0x6000 => self.setRegisterToValue(@truncate(opcode >> 8), @truncate(opcode)),
        0x7000 => self.registerAddValue(@truncate(opcode >> 8), @truncate(opcode)),
        0x8000 => switch (opcode & 0x000f) {
            0 => self.setRegisterToRegister(@truncate(opcode >> 8), @truncate(opcode >> 4)),
            1 => self.registerOrRegister(@truncate(opcode >> 8), @truncate(opcode >> 4)),
            2 => self.registerAndRegister(@truncate(opcode >> 8), @truncate(opcode >> 4)),
            3 => self.registerXorRegister(@truncate(opcode >> 8), @truncate(opcode >> 4)),
            4 => self.registerPlusRegister(@truncate(opcode >> 8), @truncate(opcode >> 4)),
            5 => self.registerMinusRegister(@truncate(opcode >> 8), @truncate(opcode >> 4)),
            6 => self.registerShiftRight(@truncate(opcode >> 8), @truncate(opcode >> 4)),
            7 => self.registerRegisterMinus(@truncate(opcode >> 8), @truncate(opcode >> 4)),
            14 => self.registerShiftLeft(@truncate(opcode >> 8), @truncate(opcode >> 4)),
            else => Chip8Error.UnknownOp,
        },
        0x9000 => self.skipRegistersNotEqual(@truncate(opcode >> 8), @truncate(opcode >> 4)),
        0xa000 => self.loadAddress(@truncate(opcode)),
        0xb000 => self.gotoAddressV0(@truncate(opcode)),
        0xc000 => self.setRegisterToRandomAndN(@truncate(opcode >> 8), @truncate(opcode)),
        0xd000 => self.drawSprite(@truncate(opcode >> 8), @truncate(opcode >> 4), @truncate(opcode)),
        0xe000 => switch ((opcode & 0x00ff)) {
            0x9e => self.skipIfKeyPressed(@truncate(opcode >> 8)),
            0xa1 => self.skipIfKeyNotPressed(@truncate(opcode >> 8)),
            else => Chip8Error.UnknownOp,
        },
        0xf000 => switch (opcode & 0x00ff) {
            0x07 => self.getDelay(@truncate(opcode >> 8)),
            0x0a => self.getKey(@truncate(opcode >> 8)),
            0x15 => self.setDelayTimer(@truncate(opcode >> 8)),
            0x18 => self.setSoundTimer(@truncate(opcode >> 8)),
            0x1e => self.addRegisterToAddress(@truncate(opcode >> 8)),
            0x29 => self.setAddressToSprite(@truncate(opcode >> 8)),
            0x33 => self.storeBinaryCodedRegister(@truncate(opcode >> 8)),
            0x55 => self.dumpRegistersUpTo(@truncate(opcode >> 8)),
            0x65 => self.loadRegistersUpTo(@truncate(opcode >> 8)),
            else => Chip8Error.UnknownOp,
        },
        else => Chip8Error.UnknownOp,
    };
}

// Opcode implementations

/// 00E0 - Clears the screen buffer.
fn clearScreen(self: *Chip8) void {
    self.screen = [_]u1{0} ** (screen_height * screen_width);
}

/// 00EE - Returns from a subroutine. Calling this function will pop the
/// top of the stack and set the program counter to that value. If there
/// are no more values in the stack, it will return an error.
fn returnFromSubroutine(self: *Chip8) Chip8Error!void {
    if (self.stack_ptr == 0) return Chip8Error.IllegalReturn;

    self.program_counter = self.stack[self.stack_ptr - 1];
    self.stack_ptr -= 1;
}

/// 1NNN - Jump to the address NNN without saving the current address.
fn gotoAddress(self: *Chip8, address: u12) void {
    self.program_counter = address;
    self.branching = true;
}

/// 2NNN - Calls a subroutine at the given address. The address is pushed onto
/// the stack and the stack pointer is incremented. If the stack is full,
/// it will return an error.
fn callSubroutine(self: *Chip8, address: u12) Chip8Error!void {
    if (self.stack_ptr == 0x5f) return Chip8Error.StackFull;

    self.stack[self.stack_ptr] = @truncate(self.program_counter);
    self.stack_ptr += 1;
    self.program_counter = @intCast(address);
    self.branching = true;
}

/// 3XNN - Skip the next opcode if the value in register X is equal to NN.
fn skipEqual(self: *Chip8, register: u4, value: u8) void {
    if (self.registers[register] == value)
        self.program_counter += 2;
}

/// 4XNN - Skip the next opcode if the value in register X is not
/// equal to NN.
fn skipNotEqual(self: *Chip8, register: u4, value: u8) void {
    if (self.registers[register] != value)
        self.program_counter += 2;
}

/// 5XY0 - Skip the next opcode if the value in register X is equal
/// to the value in register Y.
fn skipRegistersEqual(self: *Chip8, x: u4, y: u4) void {
    if (self.registers[x] == self.registers[y])
        self.program_counter += 2;
}

/// 6XNN - Set the value of register X to NN.
fn setRegisterToValue(self: *Chip8, register: u4, value: u8) void {
    self.registers[register] = value;
}

/// 7XNN - Adds the value NN to the value in register X.
fn registerAddValue(self: *Chip8, register: u4, value: u8) void {
    const result: u8 = self.registers[register] +% value;

    self.registers[register] = result;
}

/// 8XY0 - Set the value of register X to the value of register Y.
fn setRegisterToRegister(self: *Chip8, x: u4, y: u4) void {
    self.registers[x] = self.registers[y];
}

/// 8XY1 - Set the value of register X to the value of register X OR the
/// value of register Y.
fn registerOrRegister(self: *Chip8, x: u4, y: u4) void {
    self.registers[x] |= self.registers[y];
    self.registers[0xf] = 0;
}

/// 8XY2 - Set the value of register X to the value of register X AND the
/// value of register Y.
fn registerAndRegister(self: *Chip8, x: u4, y: u4) void {
    self.registers[x] &= self.registers[y];
    self.registers[0xf] = 0;
}

/// 8XY3 - Set the value of register X to the value of register X XOR the
/// value of register Y.
fn registerXorRegister(self: *Chip8, x: u4, y: u4) void {
    self.registers[x] ^= self.registers[y];
    self.registers[0xf] = 0;
}

/// 8XY4 - Adds the value of register Y to the value of register X. If the
/// result is greater than 255, it will set the carry flag to 1.
fn registerPlusRegister(self: *Chip8, x: u4, y: u4) void {
    const result: u9 = @as(u9, @intCast(self.registers[x])) + self.registers[y];
    const carry: u1 = @truncate(result >> 8);

    self.registers[x] = @truncate(result);

    self.registers[0xf] = carry;
}

/// 8XY5 - Subtracts the value of register Y from the value of register X.
/// If the value of register X is greater than the value of register Y, it
/// will set the carry flag to 1.
fn registerMinusRegister(self: *Chip8, x: u4, y: u4) void {
    const carry = self.registers[x] >= self.registers[y];

    self.registers[x] -%= self.registers[y];

    self.registers[0xf] = @intFromBool(carry);
}

/// 8XY6 - Saves the value of register Y to register X, then shifts the value
/// of register X to the right by 1. The least significant bit is stored in
/// the carry flag.
fn registerShiftRight(self: *Chip8, x: u4, y: u4) void {
    const carry = self.registers[x] & 0b0000_0001;

    self.registers[x] = self.registers[y];
    self.registers[x] >>= 1;

    self.registers[0xf] = carry;
}

/// 8XY7 - Set the value of register X to the value of register Y minus
/// the value of register X. If the value of register Y is greater than
/// the value of register X, it will set the carry flag to 1.
fn registerRegisterMinus(self: *Chip8, x: u4, y: u4) void {
    const carry = self.registers[y] >= self.registers[x];

    self.registers[x] = self.registers[y] -% self.registers[x];

    self.registers[0xf] = @intFromBool(carry);
}

/// 8XYE - Saves the value of register Y to register X, then shifts the value
/// of register X to the left by 1. The least significant bit is stored in
/// the carry flag.
fn registerShiftLeft(self: *Chip8, x: u4, y: u4) void {
    const carry = (self.registers[x] & 0b1000_0000) >> 7;

    self.registers[x] = self.registers[y];
    self.registers[x] <<= 1;

    self.registers[0xf] = carry;
}

/// 9XY0 - Skip the next opcode if the value in register X is not
/// equal to the value in register Y.
fn skipRegistersNotEqual(self: *Chip8, x: u4, y: u4) void {
    if (self.registers[x] != self.registers[y])
        self.program_counter += 2;
}

/// ANNN - Set the address register to NNN.
fn loadAddress(self: *Chip8, address: u12) void {
    self.address_register = address;
}

/// BNNN - Jump to the address NNN plus the value in register 0.
fn gotoAddressV0(self: *Chip8, address: u12) void {
    self.program_counter = address + self.registers[0];
    self.branching = true;
}

/// CXNN - Set the value of register X to a random number AND NN.
fn setRegisterToRandomAndN(self: *Chip8, x: u4, n: u8) void {
    var random_generator = std.rand.Xoshiro256.init(0);
    const random_number = random_generator.random().int(u8);
    self.registers[x] = random_number & n;
}

/// DXYN - Draws the sprite at the address stored in the address register
/// at the given coordinates. The sprite is 8 pixels wide and N pixels
/// tall. The sprite is XORed with the screen buffer. If a pixel is
/// erased, the carry flag is set to 1.
///
/// Details: Parts of sprites that are outside of the screen are not wrapped.
/// However, the sprite is wrapped around the screen if it starts outside of
/// the screen.
fn drawSprite(self: *Chip8, x: u4, y: u4, height: u4) void {
    self.registers[0xf] = 0;
    const starts_outside_y = self.registers[y] >= screen_height;
    const starts_outside_x = self.registers[x] >= screen_width;
    const screen_y_offset = if (starts_outside_y) self.registers[y] % screen_height else self.registers[y];
    const screen_x_offset = if (starts_outside_x) self.registers[x] % screen_width else self.registers[x];

    for (0..height) |sprite_y_index| {
        // Wrap the sprite around the screen only if it starts outside.
        if (screen_y_offset + sprite_y_index >= screen_height) continue;
        const screen_y_coord = screen_y_offset + sprite_y_index;
        for (0..8) |sprite_x_index| {
            // Wrap the sprite around the screen only if it starts outside.
            if (screen_x_offset + sprite_x_index >= screen_width) continue;
            const screen_x_coord = screen_x_offset + sprite_x_index;

            const sprite_pixel: u1 = @truncate(
                self.memory[self.address_register + sprite_y_index] >> (7 - @as(u3, @intCast(sprite_x_index))),
            );
            const screen_pixel_offset = @as(u16, @intCast(screen_y_coord)) * screen_width + screen_x_coord;
            const screen_pixel: u1 = (self.screen[screen_pixel_offset]) & 1;

            const new_pixel: u1 = (sprite_pixel ^ screen_pixel) & 1;
            if (sprite_pixel == 1 and screen_pixel == 1) {
                self.registers[0xf] = 1;
            }

            self.screen[screen_pixel_offset] = new_pixel;
        }
    }
}

/// EX9E - Skip the next opcode if the key corresponding to the value
/// in register X is pressed.
fn skipIfKeyPressed(self: *Chip8, register: u4) Chip8Error!void {
    const key: u8 = if (self.registers[register] < 10)
        self.registers[register] + '0'
    else if (self.registers[register] < 16)
        self.registers[register] + 'A' - 10
    else
        return Chip8Error.UnknownOp;

    if (rl.isKeyDown(@enumFromInt(key)))
        self.program_counter += 2;
}

/// EXA1 - Skip the next opcode if the key corresponding to the value
/// in register X is not pressed.
fn skipIfKeyNotPressed(self: *Chip8, register: u4) Chip8Error!void {
    const key: u8 = if (self.registers[register] < 10)
        self.registers[register] + '0'
    else if (self.registers[register] < 16)
        self.registers[register] + 'A' - 10
    else
        return Chip8Error.UnknownOp;

    if (!rl.isKeyDown(@enumFromInt(key)))
        self.program_counter += 2;
}

/// FX07 - Set the value of register X to the value of the delay timer.
fn getDelay(self: *Chip8, register: u4) void {
    self.registers[register] = self.delay_timer;
}

/// FX0A - Wait for a key press and store the value in register X.
fn getKey(self: *Chip8, register: u4) !void {
    if (self.waiting_for_key) |_|
        return;

    const key = rl.getCharPressed();

    self.registers[register] = if (key >= '0' and key <= '9')
        @as(u8, @intCast(key - '0'))
    else if (key >= 'a' and key <= 'f')
        @as(u8, @intCast(key - 'a' + 10))
    else
        return;

    self.waiting_for_key = null;
}

/// FX15 - Set the delay timer to the value of register X.
fn setDelayTimer(self: *Chip8, register: u4) void {
    self.delay_timer = self.registers[register];
}

/// FX18 - Set the sound timer to the value of register X.
fn setSoundTimer(self: *Chip8, register: u4) void {
    self.sound_timer = self.registers[register];
}

/// FX1E - Adds the value of the register X to the address register.
fn addRegisterToAddress(self: *Chip8, register: u4) void {
    self.address_register += self.registers[register];
}

/// FX29 - Set the address register to the address of the sprite
/// corresponding to the value in register X.
fn setAddressToSprite(self: *Chip8, register: u4) void {
    self.address_register = sprites_address + self.registers[register];
}

/// FX33 - Store the binary-coded decimal representation of the value in
/// register X at the address stored in the address register.
/// The hundreds digit is stored at the address, the tens digit is stored
/// at the address + 1, and the ones digit is stored at the address + 2.
fn storeBinaryCodedRegister(self: *Chip8, x: u4) !void {
    if (self.address_register > memory_size - 3)
        return Chip8Error.IllegalAddress;

    const value = self.registers[x];
    const hundreds = value / 100;
    const tens = (value % 100) / 10;
    const ones = (value % 10);

    self.memory[self.address_register] = hundreds;
    self.memory[self.address_register + 1] = tens;
    self.memory[self.address_register + 2] = ones;
}

/// FX55 - Dumps the values of the registers up to register X into memory
/// starting at the address stored in the address register.
fn dumpRegistersUpTo(self: *Chip8, reg_count: u4) void {
    for (
        self.registers[0 .. reg_count + 1],
        self.memory[self.address_register .. self.address_register + reg_count + 1],
    ) |reg, *mem| {
        mem.* = reg;
    }
    self.address_register += reg_count + 1;
}

/// FX65 - Load X bytes from the memory starting at the address stored in
/// the address register into the registers up to register X.
fn loadRegistersUpTo(self: *Chip8, reg_count: u4) void {
    for (
        self.registers[0 .. reg_count + 1],
        self.memory[self.address_register .. self.address_register + reg_count + 1],
    ) |*reg, mem| {
        reg.* = mem;
    }
    self.address_register += reg_count + 1;
}
