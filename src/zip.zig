const std = @import("std");

pub const ZipError = error{
    IllegalReturn,
    StackFull,
    UnknownOp,
};

pub const Zip = struct {
    memory: [0x1000]u8,
    registers: [0xf]u8,
    address_register: u12,
    program_counter: u16,
    stack: [0x60]u12,
    stack_ptr: u8,

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

    fn gotoAddress(self: Zip, address: u12) void {
        self.program_counter = address;
    }

    fn gotoAddressV0(self: Zip, address: u12) void {
        self.program_counter = address + self.registers[0];
    }

    fn loadAddress(self: Zip, address: u12) void {
        self.address_register = address;
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

    fn executeInstruction(self: Zip, instruction: u16) !void {
        switch (instruction & 0xf000) {
            0x0000 => switch (instruction) {
                0x00e0 => self.clearScreen(),
                0x0ee0 => self.returnFromSubroutine(),
                _ => return ZipError.UnknownOp,
            },
            0x1000 => self.gotoAddress(instruction & 0x0fff),
            0x2000 => self.callSubroutine(instruction & 0x0fff),
            0x3000 => self.skipEqual((instruction & 0x0f00) >> 16, instruction & 0xff),
            0x4000 => self.skipNotEqual((instruction & 0x0f00) >> 16, instruction & 0xff),
            0x5000 => switch (instruction & 0x000f) {
                0 => self.skipRegistersEqual((instruction & 0x0f00) >> 16, (instruction & 0x00f0) >> 8),
                _ => return ZipError.UnknownOp,
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
                _ => return ZipError.UnknownOp,
            },
            0x9000 => self.skipRegistersNotEqual((instruction & 0x0f00) >> 16, (instruction & 0x00f0) >> 8),
            0xa000 => self.loadAddress(instruction & 0x0fff),
            0xb000 => self.gotoAddressV0(instruction & 0x0fff),
            0xc000 => self.setRegisterToRandomAndN((instruction & 0x0f00) >> 16, instruction & 0x00ff),
            0xd000 => self.drawSprite((instruction & 0x0f00) >> 16, (instruction & 0x00f0) >> 8, instruction & 0x000f),
            0xe000 => switch ((instruction & 0x00ff)) {
                0x9e => self.skipIfKeyPressed((instruction & 0x0f00) >> 16),
                0xa1 => self.skipIfKeyNotPressed((instruction & 0x0f00) >> 16),
                _ => return ZipError.UnknownOp,
            },
        }
    }
};
