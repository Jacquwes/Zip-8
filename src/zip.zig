pub const Zip = struct {
    memory: [0x2000]u8,
    registers: [0xf]u8,
    address_register: u16,
};
