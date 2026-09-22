const std = @import("std");
const expectEqual = std.testing.expectEqual;

const galoisError = error{
    AlreadyExponent,
    AlreadyNonexponent,
    ValueNotFound,
};

const galois_num = struct {
    data: u8 = 0,
    is_exponent: bool = false,
    const Self = @This();

    pub fn convert_to_value(self: *Self) !void {
        if (!self.is_exponent) return galoisError.AlreadyNonexponent;
        self.data = pow2_table[self.data];
        self.is_exponent = false;
    }

    pub fn convert_to_exponent(self: *Self) !void {
        if (self.is_exponent) return galoisError.AlreadyExponent;
        self.data = @intCast(std.mem.findScalar(u8, &pow2_table, self.data) orelse return galoisError.ValueNotFound);
        self.is_exponent = true;
    }
};

pub const pow2_table: [256]u8 = blk: {
    var table: [256]u8 = undefined;
    var value: u8 = 1;
    for (&table) |*slot| {
        slot.* = value;
        value = gf_mul2(value);
    }
    break :blk table;
};

///Galois add or subtract is just bitwise XOR
///Returns the bitwise product
pub fn galois_diff(a: u8, b: u8) u8 {
    return a ^ b;
}

/// Generate next power of 2 within galois field
/// Takes in the int value of a, non exponent(not in the form of k^a)
pub fn gf_mul2(a: u8) u8 {
    var res = a << 1;
    // need to mod 285 (idk why) after multiply by 2 to stay within 256
    //285 magic num from qr tutorial, qr primitive poly
    if (a >= 128) res = galois_diff(res, 0b0001_1101);
    return res;
}

pub fn main() !void {
    for (pow2_table, 0..) |val, idx| {
        std.debug.print("2^{d}: {d}\n", .{ idx, val });
    }

    const n: galois_num = .{ .data = 20, .is_exponent = true };
    std.debug.print("data is {d} bool is {}", .{ n.data, n.is_exponent });
}

test "bitwise operations" {
    const a: u8 = 0b1010_1100;
    const b: u8 = 0b0011_0011;
    try expectEqual(
        0b1001_1111,
        galois_diff(a, b),
    );
}

test "galois multiply by 2" {
    const a: u8 = 1;
    const ans_a: u8 = 2;
    try expectEqual(ans_a, gf_mul2(a));
    const b: u8 = 128;
    const ans_b: u8 = 29;
    try expectEqual(ans_b, gf_mul2(b));
    const c: u8 = 232;
    const ans_c: u8 = 205;
    try expectEqual(ans_c, gf_mul2(c));
}

test "converting to exponent" {
    var a: galois_num = .{ .data = 8, .is_exponent = false };
    const b: galois_num = .{ .data = 3, .is_exponent = true };
    try a.convert_to_exponent();
    try expectEqual(a, b);
    var c: galois_num = .{ .data = 22, .is_exponent = false };
    const d: galois_num = .{ .data = 239, .is_exponent = true };
    try c.convert_to_exponent();
    try expectEqual(c, d);
}

test "converting to value" {
    var a: galois_num = .{ .data = 4, .is_exponent = true };
    const b: galois_num = .{ .data = 16, .is_exponent = false };
    try a.convert_to_value();
    try expectEqual(a, b);

    var c: galois_num = .{ .data = 8, .is_exponent = true };
    const d: galois_num = .{ .data = 29, .is_exponent = false };
    try c.convert_to_value();
    try expectEqual(c, d);

    var e: galois_num = .{ .data = 255, .is_exponent = true };
    const f: galois_num = .{ .data = 1, .is_exponent = false };
    try e.convert_to_value();
    try expectEqual(e, f);
}
