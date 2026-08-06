//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;

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
