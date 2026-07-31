const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

pub const ConversionError = error{
    InvalidUtf8,
    NoSpaceLeft,
};

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

fn utf8ToIso8859(string: ?[]u8) !void {
    var fallback_buf = [_]u8{'n'};

    // Now both sides are mutable ([]u8)
    const s: []u8 = string orelse &fallback_buf;
    var utf8 = (try std.unicode.Utf8View.init(s)).iterator();
    while (utf8.nextCodepointSlice()) |codepoint| {
        std.debug.print("got codepoint for {s}: {x}\n", .{ codepoint, codepoint });
    }
}

// In 0.16.0, main requires the 'init' parameter to access the new I/O system
pub fn main(init: std.process.Init) !void {
    // 1. Create buffers for stdin and stdout
    var stdin_buffer: [1024]u8 = undefined;
    var stdout_buffer: [1024]u8 = undefined;

    // 2. Create the reader and writer using the NEW std.Io.File API
    var stdin_wrapper = std.Io.File.stdin().reader(init.io, &stdin_buffer);
    const stdin = &stdin_wrapper.interface;

    var stdout_wrapper = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_wrapper.interface;

    // 3. Prompt the user
    try stdout.writeAll("Enter text: ");
    try stdout.flush(); // CRITICAL: Forces the prompt to appear on screen immediately

    // 4. Read until the user presses Enter ('\n')
    // We use 'catch' to gracefully handle EOF (e.g., if the user presses Ctrl+D)
    const line = stdin.takeDelimiter('\n') catch |err| {
        if (err == error.EndOfStream) {
            try stdout.writeAll("\nNo input received.\n");
            try stdout.flush();
            return;
        }
        return err;
    };

    var out_buffer: [4096]u8 = undefined;
    var iso_result: []u8 = undefined;
    if (line) |text| {
        iso_result = try utf8ToIso8859lossy(text, &out_buffer);
    } else {
        unreachable;
    }

    std.debug.print("Original UTF-8: {s}\n", .{line orelse "(no val)"});
    std.debug.print("ISO-8859-1 hex: ", .{});

    for (iso_result) |byte| {
        std.debug.print("{X:0>2} ", .{byte});
    }
    std.debug.print("\n", .{});

    // 5. Process and print the result
    if (line) |text| {
        // Trim Windows-specific carriage return ("\r") if present
        // const clean_line = std.mem.trimRight(u8, text, "\r");

        try stdout.print("You typed: {s}\n", .{text});
        try stdout.flush();
    }
    try stdout.print("Press enter to exit...\n", .{});
    try stdout.flush();
    _ = try stdin.takeDelimiterExclusive('\n');
}

test "converting emoji" {
    const test_input = "Yowasap 😀";

    var out_buffer: [4096]u8 = undefined;
    const iso_result = try utf8ToIso8859lossy(test_input, &out_buffer);

    std.debug.print("Hex output: ", .{});
    for (iso_result) |byte| {
        std.debug.print("{X:0>2} ", .{byte});
    }
    std.debug.print("\n", .{});

    try expect(true);
}
