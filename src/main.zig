const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const rl = @import("raylib");
const util = @import("root.zig");

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

    // Making a raylib stuff
    rl.initWindow(1280, 720, "raylib texting");
    defer rl.closeWindow();

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.sky_blue);

        rl.drawText("This is the first window!", 20, 20, 20, .black);
    }

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
        iso_result = try util.utf8ToIso8859lossy(text, &out_buffer);
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
    const iso_result = try util.utf8ToIso8859lossy(test_input, &out_buffer);

    std.debug.print("Hex output: ", .{});
    for (iso_result) |byte| {
        std.debug.print("{X:0>2} ", .{byte});
    }
    std.debug.print("\n", .{});

    try expect(true);
}
