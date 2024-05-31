const std = @import("std");
const log = std.log;

pub const std_options: std.Options = .{
    .logFn = logFn,
    .log_level = .debug,
};

fn logFn(
    comptime message_level: log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = comptime message_level.asText();
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    var buf: [256]u8 = undefined;
    const line = std.fmt.bufPrint(&buf, level_txt ++ prefix2 ++ format, args) catch line: {
        buf[buf.len - 3 ..][0..3].* = "...".*;
        break :line &buf;
    };
    pf.output_line_to_console(line);
}

// TODO: better panic
pub fn panic(msg: []const u8, st: ?*std.builtin.StackTrace, addr: ?usize) noreturn {
    _ = st;
    _ = addr;
    log.err("{s}", .{msg});
    @trap();
}

const Game = @import("Game.zig");
const pf = @import("platform.zig");

var game: Game = undefined;

fn frame() void {
    game.frame();
}

export fn wasm__init(w: i32, h: i32) void {
    const gpa = std.heap.wasm_allocator;

    game = Game.init(gpa, w, h);

    pf.set_frame_callback(frame);
}
