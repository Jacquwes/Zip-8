pub const ZipError = error{
    IllegalReturn,
    StackFull,
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

    fn gotoAddress(self: Zip, address: u12) void {
        self.program_counter = address;
    }

    fn returnFromSubroutine(self: Zip) !void {
        if (self.stack_ptr == 0) return ZipError.IllegalReturn;

        self.program_counter = self.stack[self.stack_ptr - 1];
        self.stack_ptr -= 1;
    }

    fn skipEqual(self: Zip, register: u4, value: u8) void {
        if (self.registers[register] == value)
            self.program_counter += 1;
    }

    fn executeInstruction(self: Zip, instruction: u16) !void {
        switch (instruction & 0xf000) {
            0 => switch (instruction) {
                0x00e0 => self.clearScreen(),
                0x0ee0 => self.returnFromSubroutine(),
            },
            1 => self.gotoAddress(instruction & 0x0fff),
            2 => self.callSubroutine(instruction & 0x0fff),
            3 => self.skipEqual((instruction & 0x0f00) >> 16, instruction & 0xff),
        }
    }
};
