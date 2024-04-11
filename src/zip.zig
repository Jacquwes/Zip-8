const std = @import("std");

pub const ZipError = error{
    IllegalReturn,
    StackFull,
    UnknownOp,
};

pub const Zip = struct {
    memory: [0x1000]u8,
    registers: [0x10]u8,

    address_register: u12,
    program_counter: u16,

    stack: [0x60]u12,
    stack_ptr: u8,

    delay_timer: u8,
    sound_timer: u8,

    const sprites_address: u12 = 0;
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

    pub fn init() Zip {
        return .{
            .address_register = 0,
            .delay_timer = 0,
            .memory = [_]u8{0} ** 0x1000,
            .program_counter = 0,
            .registers = [_]u8{0} ** 0x10,
            .sound_timer = 0,
            .stack = [_]u12{0} ** 0x60,
            .stack_ptr = 0,
        };
    }

    fn AddRegisterToAddress(self: Zip, register: u4) void {
        self.address_register += self.registers[register];
    }

    fn callSubroutine(self: Zip, address: u12) !void {
        if (self.stack_ptr == 0x5f) return ZipError.StackFull;

        self.stack[self.stack_ptr] = address;
        self.stack_ptr += 1;
    }

    // TODO: implement screen
    fn clearScreen(self: Zip) void {
        _ = self;
    }

    fn drawSprite(self: Zip, x: u4, y: u4, height: u4) void {
        _ = height;
        _ = y;
        _ = x;
        _ = self;
    }

    fn dumpRegistersUpTo(self: Zip, register: u4) void {
        for (self.registers, 0..register) |value, i| {
            self.memory[i + self.address_register] = value;
        }
    }

    fn getDelay(self: Zip, register: u4) void {
        self.registers[register] = self.delay_timer;
    }

    // TODO
    fn getKey(self: Zip, register: u4) !void {
        _ = register;
        _ = self;
    }

    fn gotoAddress(self: Zip, address: u12) void {
        self.program_counter = address;
    }

    fn gotoAddressV0(self: Zip, address: u12) void {
        self.program_counter = address + self.registers[0];
    }

    fn loadAddress(self: Zip, address: u12) void {
        self.address_register = address;
    }

    fn loadRegistersUpTo(self: Zip, register: u4) void {
        for (0..register) |i| {
            self.registers[i] = self.memory[self.address_register + i];
        }
    }

    fn registerMinusRegister(self: Zip, x: u4, y: u4) void {
        if (self.registers[x] >= self.registers[y])
            self.registers[0xf] = 1;

        self.registers[x] -= self.registers[y];
    }

    fn registerPlusRegister(self: Zip, x: u4, y: u4) void {
        self.registers[x] += self.registers[y];
    }

    fn registerAddValue(self: Zip, register: u4, value: u8) void {
        const result: u8 = (self.registers[register] + value) % 0x100;

        self.registers[register] = result;
    }

    fn registerAndRegister(self: Zip, x: u4, y: u4) void {
        self.registers[x] &= self.registers[y];
    }

    fn registerRegisterMinus(self: Zip, x: u4, y: u4) void {
        if (self.registers[y] >= self.registers[x])
            self.registers[0xf] = 1;

        self.registers[x] = self.registers[y] - self.registers[x];
    }

    fn registerShiftLeft(self: Zip, register: u4) void {
        self.registers[0xf] = (self.registers[register] & 0b1000_0000) >> 7;

        self.registers[register] <<= 1;
    }

    fn registerShiftRight(self: Zip, register: u4) void {
        self.registers[0xf] = self.registers[register] & 1;

        self.registers[register] >>= 1;
    }

    fn registerOrRegister(self: Zip, x: u4, y: u4) void {
        self.registers[x] |= self.registers[y];
    }

    fn registerXorRegister(self: Zip, x: u4, y: u4) void {
        self.registers[x] ^= self.registers[y];
    }

    fn returnFromSubroutine(self: Zip) !void {
        if (self.stack_ptr == 0) return ZipError.IllegalReturn;

        self.program_counter = self.stack[self.stack_ptr - 1];
        self.stack_ptr -= 1;
    }

    fn setAddressToSprite(self: Zip, register: u4) void {
        self.address_register = sprites_address + self.registers[register];
    }

    fn setDelayTimer(self: Zip, register: u4) void {
        self.delay_timer = self.registers[register];
    }

    fn setRegisterToRegister(self: Zip, x: u4, y: u4) void {
        self.registers[x] = self.registers[y];
    }

    fn setRegisterToValue(self: Zip, register: u4, value: u8) void {
        self.registers[register] = value;
    }

    fn setRegisterToRandomAndN(self: Zip, x: u4, n: u8) void {
        const random_generator = std.rand.Xoshiro256.init(0);
        const random_number = random_generator.random().int(u8);
        self.registers[x] = random_number & n;
    }

    fn setSoundTimer(self: Zip, register: u4) void {
        self.sound_timer = self.registers[register];
    }

    fn skipEqual(self: Zip, register: u4, value: u8) void {
        if (self.registers[register] == value)
            self.program_counter += 1;
    }

    // TODO: Implement keys
    fn skipIfKeyPressed(self: Zip, register: u4) void {
        _ = register;
        _ = self;
    }

    fn skipIfKeyNotPressed(self: Zip, register: u4) void {
        _ = register;
        _ = self;
    }

    fn skipNotEqual(self: Zip, register: u4, value: u8) void {
        if (self.registers[register] != value)
            self.program_counter += 1;
    }

    fn skipRegistersEqual(self: Zip, x: u4, y: u4) void {
        if (self.register[x] == self.registers[y])
            self.program_counter += 1;
    }

    fn skipRegistersNotEqual(self: Zip, x: u4, y: u4) void {
        if (self.registers[x] != self.registers[y])
            self.program_counter += 1;
    }

    fn storeBinaryCodedRegister(self: Zip, x: u4) !void {
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

    fn executeInstruction(self: Zip, instruction: u16) !void {
        return switch (instruction & 0xf000) {
            0x0000 => switch (instruction) {
                0x00e0 => self.clearScreen(),
                0x0ee0 => self.returnFromSubroutine(),
                _ => ZipError.UnknownOp,
            },
            0x1000 => self.gotoAddress(instruction & 0x0fff),
            0x2000 => self.callSubroutine(instruction & 0x0fff),
            0x3000 => self.skipEqual((instruction & 0x0f00) >> 16, instruction & 0xff),
            0x4000 => self.skipNotEqual((instruction & 0x0f00) >> 16, instruction & 0xff),
            0x5000 => switch (instruction & 0x000f) {
                0 => self.skipRegistersEqual((instruction & 0x0f00) >> 16, (instruction & 0x00f0) >> 8),
                _ => ZipError.UnknownOp,
            },
            0x6000 => self.setRegisterToValue((instruction & 0x0f00) >> 16, instruction & 0x00ff),
            0x7000 => self.registerAddValue((instruction & 0x0f00) >> 16, instruction & 0x00ff),
            0x8000 => switch (instruction & 0x000f) {
                0 => self.setRegisterToRegister((instruction & 0x0f00) >> 16, (instruction & 0x00f0) >> 8),
                1 => self.registerOrRegister((instruction & 0x0f00) >> 16, (instruction & 0x00f0) >> 8),
                2 => self.registerAndRegister((instruction & 0x0f00) >> 16, (instruction & 0x00f0) >> 8),
                3 => self.registerXorRegister((instruction & 0x0f00) >> 16, (instruction & 0x00f0) >> 8),
                4 => self.registerPlusRegister((instruction & 0x0f00) >> 16, (instruction & 0x00f0) >> 8),
                5 => self.registerMinusRegister((instruction & 0x0f00) >> 16, (instruction & 0x00f0) >> 8),
                6 => self.registerShiftRight((instruction & 0x0f00) >> 16, (instruction & 0x00f0) >> 8),
                7 => self.registerRegisterMinus((instruction & 0x0f00) >> 16, (instruction & 0x00f0) >> 8),
                14 => self.registerShiftLeft((instruction & 0x0f00) >> 16, (instruction & 0x00f0) >> 8),
                _ => ZipError.UnknownOp,
            },
            0x9000 => self.skipRegistersNotEqual((instruction & 0x0f00) >> 16, (instruction & 0x00f0) >> 8),
            0xa000 => self.loadAddress(instruction & 0x0fff),
            0xb000 => self.gotoAddressV0(instruction & 0x0fff),
            0xc000 => self.setRegisterToRandomAndN((instruction & 0x0f00) >> 16, instruction & 0x00ff),
            0xd000 => self.drawSprite((instruction & 0x0f00) >> 16, (instruction & 0x00f0) >> 8, instruction & 0x000f),
            0xe000 => switch ((instruction & 0x00ff)) {
                0x9e => self.skipIfKeyPressed((instruction & 0x0f00) >> 16),
                0xa1 => self.skipIfKeyNotPressed((instruction & 0x0f00) >> 16),
                _ => ZipError.UnknownOp,
            },
            0xf000 => switch (instruction & 0x00ff) {
                0x07 => self.getDelay((instruction & 0x0f00) >> 16),
                0x0a => self.getKey((instruction & 0x0f00) >> 16),
                0x15 => self.setDelayTimer((instruction & 0x0f00) >> 16),
                0x18 => self.setSoundTimer((instruction & 0x0f00) >> 16),
                0x1e => self.AddRegisterToAddress((instruction & 0x0f00) >> 16),
                0x29 => self.setAddressToSprite((instruction & 0x0f00) >> 16),
                0x33 => self.storeBinaryCodedRegister((instruction & 0x0f00) >> 16),
                0x55 => self.dumpRegistersUpTo((instruction & 0x0f00) >> 16),
                0x65 => self.loadRegistersUpTo((instruction & 0x0f00) >> 16),
                _ => ZipError.UnknownOp,
            },
            _ => ZipError.UnknownOp,
        };
    }
};
