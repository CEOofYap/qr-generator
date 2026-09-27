const std = @import("std");
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const ArrayList = std.ArrayList;
const test_alc = std.testing.allocator;

const galoisError = error{
    AlreadyExponent,
    AlreadyNonexponent,
    ValueNotFound,
};

pub const galois_num = struct {
    data: u8 = 0,
    is_exponent: bool = false,
    const Self = @This();

    pub fn isZero(self: Self) bool {
        return !self.is_exponent and self.data == 0;
    }

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

    /// convert 2 galois num into exponent form and multiply it
    /// always return in exponent form unless result is 0
    pub fn mul(a: Self, b: Self) Self {
        var x = a;
        var y = b;
        if (!x.is_exponent) {
            // any num multiply with 0 is 0
            if (x.data == 0) return .{ .data = 0, .is_exponent = false };
            //  convert to exponent
            x.convert_to_exponent() catch unreachable;
        }
        if (!y.is_exponent) {
            // any num multiply with 0 is 0
            if (y.data == 0) return .{ .data = 0, .is_exponent = false };
            //  convert to exponent
            y.convert_to_exponent() catch unreachable;
        }

        return .{
            .data = @intCast((@as(u16, x.data) + y.data) % 255),
            .is_exponent = true,
        };
    }

    /// convert 2 galois num into value form and add it
    /// always return in value form
    pub fn add(a: Self, b: Self) Self {
        var x = a;
        var y = b;
        if (x.is_exponent) {
            //  convert to value
            x.convert_to_value() catch unreachable;
        }
        if (y.is_exponent) {
            //  convert to value
            y.convert_to_value() catch unreachable;
        }

        return .{
            .data = x.data ^ y.data,
            .is_exponent = false,
        };
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

pub const polynomial = struct {
    coef: ArrayList(galois_num) = .empty,
    allocator: std.mem.Allocator,
    const Self = @This();

    /// Create arraylist of coefficient based on power.
    /// 0 -> (x^0) one element, 1 -> 2 element (x^1 + x^0)
    /// coef[0] is x^0, coef[n] is x^n.
    pub fn init(polynomial_power: usize, allocator: std.mem.Allocator) !Self {
        var self = Self{
            .coef = .empty,
            .allocator = allocator,
        };
        try self.coef.appendNTimes(
            allocator,
            .{ .data = 0, .is_exponent = false },
            polynomial_power + 1,
        );
        return self;
    }
    pub fn deinit(self: *Self) void {
        self.coef.deinit(self.allocator);
    }

    /// Test / convenience constructor from raw values (value-form).
    /// `&.{ 1, 4, 2 }` means 1 + 4*x + 2*x^2, i.e. coef[0] is x^0.
    pub fn fromValues(allocator: std.mem.Allocator, values: []const u8) !Self {
        var self = Self{
            .coef = .empty,
            .allocator = allocator,
        };
        for (values) |v| {
            try self.coef.append(allocator, .{ .data = v, .is_exponent = false });
        }
        self.normalize();
        return self;
    }

    /// Drop highest-degree zero coefficients (trailing items, since coef[0] is x^0).
    /// Keeps at least one coefficient so zero poly stays as [0].
    pub fn normalize(self: *Self) void {
        while (self.coef.items.len > 1 and self.coef.items[self.coef.items.len - 1].isZero()) {
            _ = self.coef.pop();
        }
    }

    pub fn normalizeToExponent(self: *Self) !void {
        for (self.coef.items) |*coefficient| {
            if (coefficient.isZero()) continue;
            if (!coefficient.is_exponent) try coefficient.convert_to_exponent();
        }
    }

    /// coef[0] is x^0, so (a_i * x^i) * (b_j * x^j) accumulates into res[i + j].
    pub fn mul(a: Self, b: Self) !Self {
        const len_a = a.coef.items.len;
        const len_b = b.coef.items.len;
        if (len_a == 0 or len_b == 0) return Self{ .coef = .empty, .allocator = a.allocator };

        // deg = len-1, so result deg = (len_a-1) + (len_b-1)
        const result_power: usize = (len_a - 1) + (len_b - 1);
        var res: Self = try .init(result_power, a.allocator);

        for (a.coef.items, 0..) |a_coefficient, i| {
            for (b.coef.items, 0..) |b_coefficient, j| {
                const prod = galois_num.mul(a_coefficient, b_coefficient);
                res.coef.items[i + j] = galois_num.add(prod, res.coef.items[i + j]);
            }
        }
        return res;
    }

    /// Coefficient-wise XOR. Missing coefficients (unequal lengths) count as 0.
    pub fn add(a: Self, b: Self) !Self {
        const len_a = a.coef.items.len;
        const len_b = b.coef.items.len;
        const max_len = @max(len_a, len_b);
        if (max_len == 0) return Self{ .coef = .empty, .allocator = a.allocator };

        var res: Self = try .init(max_len - 1, a.allocator);
        const zero: galois_num = .{ .data = 0, .is_exponent = false };

        for (res.coef.items, 0..) |*c, i| {
            const av = if (i < len_a) a.coef.items[i] else zero;
            const bv = if (i < len_b) b.coef.items[i] else zero;
            c.* = galois_num.add(av, bv);
        }
        res.normalize();
        return res;
    }
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
    try a.convert_to_exponent();
    try expectEqual(@as(u8, 3), a.data);
    try expectEqual(true, a.is_exponent);
    var c: galois_num = .{ .data = 22, .is_exponent = false };
    try c.convert_to_exponent();
    try expectEqual(@as(u8, 239), c.data);
    try expectEqual(true, c.is_exponent);
}

test "converting to value" {
    var a: galois_num = .{ .data = 4, .is_exponent = true };
    try a.convert_to_value();
    try expectEqual(@as(u8, 16), a.data);
    try expectEqual(false, a.is_exponent);

    var c: galois_num = .{ .data = 8, .is_exponent = true };
    try c.convert_to_value();
    try expectEqual(@as(u8, 29), c.data);
    try expectEqual(false, c.is_exponent);

    var e: galois_num = .{ .data = 255, .is_exponent = true };
    try e.convert_to_value();
    try expectEqual(@as(u8, 1), e.data);
    try expectEqual(false, e.is_exponent);
}

test "galois mul" {
    // value 2 (2^1) * value 4 (2^2) = exp 3 (2^3 = 8)
    var got = galois_num.mul(
        .{ .data = 2, .is_exponent = false },
        .{ .data = 4, .is_exponent = false },
    );
    try expectEqual(@as(u8, 3), got.data);
    try expectEqual(true, got.is_exponent);

    // mixed forms: exp 1 * value 4 = exp 3
    got = galois_num.mul(
        .{ .data = 1, .is_exponent = true },
        .{ .data = 4, .is_exponent = false },
    );
    try expectEqual(@as(u8, 3), got.data);
    try expectEqual(true, got.is_exponent);

    // exp 0 is value 1, identity: exp 17 * exp 0 = exp 17
    got = galois_num.mul(
        .{ .data = 17, .is_exponent = true },
        .{ .data = 0, .is_exponent = true },
    );
    try expectEqual(@as(u8, 17), got.data);
    try expectEqual(true, got.is_exponent);

    // exponent wraps mod 255: (200 + 100) % 255 = 45
    got = galois_num.mul(
        .{ .data = 200, .is_exponent = true },
        .{ .data = 100, .is_exponent = true },
    );
    try expectEqual(@as(u8, 45), got.data);
    try expectEqual(true, got.is_exponent);

    // zero absorbs: any num * 0 = 0 in value form
    got = galois_num.mul(
        .{ .data = 0, .is_exponent = false },
        .{ .data = 7, .is_exponent = false },
    );
    try expectEqual(@as(u8, 0), got.data);
    try expectEqual(false, got.is_exponent);

    // zero absorbs exponent-form operand too
    got = galois_num.mul(
        .{ .data = 0, .is_exponent = false },
        .{ .data = 10, .is_exponent = true },
    );
    try expectEqual(@as(u8, 0), got.data);
    try expectEqual(false, got.is_exponent);
}

test "galois add" {
    // value 12 + value 10 = 12 ^ 10 = 6
    var got = galois_num.add(
        .{ .data = 12, .is_exponent = false },
        .{ .data = 10, .is_exponent = false },
    );
    try expectEqual(@as(u8, 6), got.data);
    try expectEqual(false, got.is_exponent);

    // exp 1 (value 2) + exp 2 (value 4) = 2 ^ 4 = 6
    got = galois_num.add(
        .{ .data = 1, .is_exponent = true },
        .{ .data = 2, .is_exponent = true },
    );
    try expectEqual(@as(u8, 6), got.data);
    try expectEqual(false, got.is_exponent);

    // exp 3 (value 8) + value 12: 8 ^ 12 = 4
    got = galois_num.add(
        .{ .data = 3, .is_exponent = true },
        .{ .data = 12, .is_exponent = false },
    );
    try expectEqual(@as(u8, 4), got.data);
    try expectEqual(false, got.is_exponent);

    // zero is identity: 0 + 5 = 5
    got = galois_num.add(
        .{ .data = 0, .is_exponent = false },
        .{ .data = 5, .is_exponent = false },
    );
    try expectEqual(@as(u8, 5), got.data);
    try expectEqual(false, got.is_exponent);

    // self + self = 0: 7 ^ 7 = 0
    got = galois_num.add(
        .{ .data = 7, .is_exponent = false },
        .{ .data = 7, .is_exponent = false },
    );
    try expectEqual(@as(u8, 0), got.data);
    try expectEqual(false, got.is_exponent);
}

test "convert errors" {
    // 0 has no exponent: absent from pow2_table
    var zero: galois_num = .{ .data = 0, .is_exponent = false };
    try expectError(error.ValueNotFound, zero.convert_to_exponent());

    // already exponent
    var exp: galois_num = .{ .data = 1, .is_exponent = true };
    try expectError(error.AlreadyExponent, exp.convert_to_exponent());

    // already value
    var val: galois_num = .{ .data = 5, .is_exponent = false };
    try expectError(error.AlreadyNonexponent, val.convert_to_value());
}

fn expectPolyValues(poly: *const polynomial, expected: []const u8) !void {
    try std.testing.expectEqual(expected.len, poly.coef.items.len);
    for (expected, 0..) |v, i| {
        try std.testing.expectEqual(v, poly.coef.items[i].data);
        try std.testing.expectEqual(false, poly.coef.items[i].is_exponent);
    }
}

test "polynomial fromValues trims leading zeros" {
    var p = try polynomial.fromValues(test_alc, &.{ 1, 0, 0 });
    defer p.deinit();
    try expectPolyValues(&p, &.{1});
}

test "polynomial add same length xors coefficients" {
    var a = try polynomial.fromValues(test_alc, &.{ 1, 2 });
    defer a.deinit();
    var b = try polynomial.fromValues(test_alc, &.{ 3, 4 });
    defer b.deinit();
    var res = try polynomial.add(a, b);
    defer res.deinit();
    // 1^3=2, 2^4=6
    try expectPolyValues(&res, &.{ 2, 6 });
}

test "polynomial add pads shorter operand with zeros" {
    var a = try polynomial.fromValues(test_alc, &.{ 1, 2, 3 });
    defer a.deinit();
    var b = try polynomial.fromValues(test_alc, &.{4});
    defer b.deinit();
    var res = try polynomial.add(a, b);
    defer res.deinit();
    // 1^4=5, rest unchanged
    try expectPolyValues(&res, &.{ 5, 2, 3 });
}

test "polynomial add trims leading zero to single zero" {
    var a = try polynomial.fromValues(test_alc, &.{ 5, 3 });
    defer a.deinit();
    var b = try polynomial.fromValues(test_alc, &.{ 5, 3 });
    defer b.deinit();
    var res = try polynomial.add(a, b);
    defer res.deinit();
    try expectPolyValues(&res, &.{0});
}
test "polynomial mul" {
    var a = try polynomial.fromValues(test_alc, &.{ 1, 4, 2 });
    defer a.deinit();
    var b = try polynomial.fromValues(test_alc, &.{ 3, 5 });
    defer b.deinit();
    var res = try polynomial.mul(a, b);
    defer res.deinit();
    // coef[0] is x^0: [1,4,2]*[3,5] = [3,9,18,10] in GF
    try std.testing.expectEqual(@as(usize, 4), res.coef.items.len);
    try std.testing.expectEqualSlices(u8, &.{ 3, 9, 18, 10 }, &.{
        res.coef.items[0].data,
        res.coef.items[1].data,
        res.coef.items[2].data,
        res.coef.items[3].data,
    });
}
