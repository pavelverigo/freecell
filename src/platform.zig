const std = @import("std");

///
var mouse_inside = false;

export fn wasm__update_mouse_inside(cond: bool) void {
    mouse_inside = cond;
}

pub fn is_mouse_inside() bool {
    return mouse_inside;
}

///
var mouse_x: i32 = 0;
var mouse_y: i32 = 0;

export fn wasm__update_mouse_position(x: i32, y: i32) void {
    mouse_x = x;
    mouse_y = y;
}

pub fn get_mouse_x() i32 {
    return mouse_x;
}

pub fn get_mouse_y() i32 {
    return mouse_y;
}

///
pub const ButtonName = enum { main, auxilary, secondary };
pub const ButtonPosition = enum { up, down };
var mouse_buttons = std.EnumArray(ButtonName, ButtonPosition).initFill(.up);

export fn wasm__update_mouse_button_state(name: i32, state: i32) void {
    mouse_buttons.set(@enumFromInt(name), @enumFromInt(state));
}

pub fn is_mouse_button_up(name: ButtonName) bool {
    return mouse_buttons.get(name) == .up;
}

pub fn is_mouse_button_down(name: ButtonName) bool {
    return mouse_buttons.get(name) == .down;
}

///
extern fn js__output_image_data(ptr: [*]const u32, len: usize) void;

pub fn output_image_data(data: []const u32) void {
    js__output_image_data(data.ptr, data.len);
}

///
extern fn js__play_sound(ptr: [*]const u8, len: usize) void;

pub fn play_sound(name: []const u8) void {
    js__play_sound(name.ptr, name.len);
}

///
extern fn js__get_timestamp() f64;

pub fn get_timestamp() f64 {
    return js__get_timestamp();
}

///
extern fn js__get_random_u32() u32;

pub fn get_random_u32() u32 {
    return js__get_random_u32();
}

///
extern fn js__output_line_to_console(ptr: [*]const u8, len: usize) void;

pub fn output_line_to_console(buf: []const u8) void {
    js__output_line_to_console(buf.ptr, buf.len);
}

///
var frame_callback: ?*const fn () void = null;

export fn wasm__frame() void {
    if (frame_callback) |f| f();
}

pub fn set_frame_callback(f: ?*const fn () void) void {
    frame_callback = f;
}
