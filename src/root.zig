//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;
const ArrayList = std.ArrayList;

/// This is a documentation comment to explain the `printAnotherMessage` function below.
///
/// Accepting an `Io.Writer` instance is a handy way to write reusable code.
pub const ConversionError = error{
    InvalidUtf8,
    NoSpaceLeft,
};

pub fn printAnotherMessage(writer: *Io.Writer) Io.Writer.Error!void {
    try writer.print("Run `zig build test` to run the tests.\n", .{});
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}

pub fn utf8ToIso8859lossy(utf8: []const u8, out: []u8) ConversionError![]u8 {
    var view = try std.unicode.Utf8View.init(utf8);
    var it = view.iterator();
    var idx: usize = 0;
    while (it.nextCodepoint()) |codepoint| {
        std.debug.print("got codepoint for {u}: {x}\n", .{ codepoint, codepoint });

        if (codepoint <= 255) {
            out[idx] = @as(u8, @intCast(codepoint));
        } else {
            out[idx] = '?';
        }
        idx += 1;
    }

    return out[0..idx];
}

pub const QrMatrix = struct {
    data: []u8,
    size: usize,
    allocator: std.mem.Allocator,

    pub fn init(a: std.mem.Allocator, size: usize) !QrMatrix {
        const data = try a.alloc(u8, size * size);
        @memset(data, 0); // Initialize all cells to 0

        return .{
            .data = data,
            .size = size,
            .allocator = a,
        };
    }
    pub fn deinit(self: QrMatrix) void {
        self.allocator.free(self.data);
    }
    // Helper to translate 2D coordinates to our 1D slice
    pub fn get(self: QrMatrix, x: usize, y: usize) u8 {
        return self.data[y * self.size + x];
    }
    pub fn set(self: *QrMatrix, x: usize, y: usize, value: u8) void {
        self.data[y * self.size + x] = value;
    }
    pub fn print(self: QrMatrix) void {
        for (self.data, 0..) |bit, idx| {
            if (bit == 0) {
                std.debug.print("0", .{});
            } else {
                std.debug.print("1", .{});
            }
            if ((idx + 1) % self.size == 0 and idx != 0) {
                std.debug.print("\n", .{});
            }
        }
    }
};

pub fn main() !void {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const alc = arena.allocator();

    const runtime_size: usize = 5;

    var matrix: QrMatrix = try QrMatrix.init(alc, runtime_size);
    defer matrix.deinit();
    matrix.set(0, 0, 0);
    matrix.set(1, 0, 1);
    matrix.set(0, 1, 0);
    matrix.set(1, 1, 1);
    matrix.set(0, 4, 1);

    matrix.print();
}
