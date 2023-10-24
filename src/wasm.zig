const std = @import("std");
const game = @import("game.zig");
const d2 = @import("d2.zig");

extern fn _fullscreen(bool) void;

pub fn fullscreen(mode: bool) void {
    _fullscreen(mode);
}

pub extern fn _win_sound() void;
pub extern fn _card_sound() void;

extern fn _print(usize, usize) void;

pub fn print(comptime fmt: []const u8, args: anytype) void {
    var buf: [1024]u8 = undefined;
    var out = std.fmt.bufPrint(&buf, fmt, args) catch unreachable;
    _print(@intFromPtr(out.ptr), out.len);
}

extern fn _seed() u32;

pub fn seed() u32 {
    return _seed();
}

// TODO SYNC with build.zig
const heap_pages = 256;
var allocator: std.mem.Allocator = undefined;

export fn _init(w: i32, h: i32) [*]d2.RGBA {
    var heap_slice = @as([*]u8, @ptrFromInt(64 * 1024))[0 .. heap_pages * 64 * 1024];
    var fixed_buffer = std.heap.FixedBufferAllocator.init(heap_slice);
    allocator = fixed_buffer.allocator();

    const main_image: d2.Image = .{
        .data = allocator.alloc(d2.RGBA, @intCast(w * h)) catch unreachable,
        .w = w,
        .h = h,
    };

    game.init(main_image);

    return main_image.data.ptr;
}

export fn _resize(w: i32, h: i32) [*]d2.RGBA {
    var heap_slice = @as([*]u8, @ptrFromInt(64 * 1024))[0 .. heap_pages * 64 * 1024];
    var fixed_buffer = std.heap.FixedBufferAllocator.init(heap_slice);
    allocator = fixed_buffer.allocator();

    const main_image: d2.Image = .{
        .data = allocator.alloc(d2.RGBA, @intCast(w * h)) catch unreachable,
        .w = w,
        .h = h,
    };

    game.resize(main_image);

    return main_image.data.ptr;
}

export fn _frame(mx: i32, my: i32, inside: bool, pressed: bool, time: f32) void {
    game.frame(mx, my, inside, pressed, time);
}

export fn _fullscreen_mode(mode: bool) void {
    game.fullscreen_mode(mode);
}
