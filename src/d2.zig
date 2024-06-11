const std = @import("std");
const Rect = @import("Rect.zig");
const Sprite = @import("Sprite");

pub const RGBA = packed struct(u32) {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

pub const Surface = struct {
    pixels: []RGBA,
    w: i32,
    h: i32,
};

inline fn blend_pixel_no_alpha(dest: RGBA, src: RGBA) RGBA {
    _ = dest;
    return src;
}

inline fn blend_pixel_simple_alpha(dest: RGBA, src: RGBA) RGBA {
    return if (src.a != 0) src else dest;
}

inline fn blend_pixel(dest: RGBA, src: RGBA) RGBA {
    const ra = 0xFF - src.a;
    var res = dest;
    res.r = @intCast((@as(u16, src.r) * src.a + @as(u16, dest.r) * ra) >> 8);
    res.g = @intCast((@as(u16, src.g) * src.a + @as(u16, dest.g) * ra) >> 8);
    res.b = @intCast((@as(u16, src.b) * src.a + @as(u16, dest.b) * ra) >> 8);
    return res;
}

inline fn draw_rect_loop(surf: Surface, dest_rect: Rect, color: RGBA, comptime blend: fn (RGBA, RGBA) callconv(.Inline) RGBA) void {
    var i: usize = @intCast(dest_rect.y * surf.w + dest_rect.x);
    var dy: i32 = 0;
    while (dy < dest_rect.h) : (dy += 1) {
        var dx: i32 = 0;
        while (dx < dest_rect.w) : (dx += 1) {
            surf.pixels[i] = blend(surf.pixels[i], color);
            i += 1;
        }
        i += @intCast(surf.w - dest_rect.w);
    }
}

fn draw_rect_to_surface(surf: Surface, dest_rect: Rect, color: RGBA) void {
    if (color.a == 0xFF) {
        draw_rect_loop(surf, dest_rect, color, blend_pixel_no_alpha);
    } else if (color.a > 0) {
        draw_rect_loop(surf, dest_rect, color, blend_pixel);
    }
}

fn draw_sprite_to_surface(surf: Surface, dest_rect: Rect, sprite: *const Sprite, offset_x: i32, offset_y: i32) void {
    var i: usize = @intCast(dest_rect.y * surf.w + dest_rect.x);
    var j: usize = @intCast(offset_y * sprite.w + offset_x);
    var dy: i32 = 0;
    while (dy < dest_rect.h) : (dy += 1) {
        var dx: i32 = 0;
        while (dx < dest_rect.w) : (dx += 1) {
            const src: RGBA = @bitCast(sprite.pixels[j]);
            if (src.a == 0xFF) {
                surf.pixels[i] = src;
            } else if (src.a > 0x00) {
                // unreachable; // TODO
            }
            i += 1;
            j += 1;
        }
        i += @intCast(surf.w - dest_rect.w);
        j += @intCast(sprite.w - dest_rect.w);
    }
}

pub const Canvas = CachedCanvas;

pub fn draw_monogram_text(c: *Canvas, text: []const u8, x: i32, y: i32, dx: i32) void {
    var cur_x: i32 = x;
    for (text) |char| {
        const sprite = if (32 <= char and char <= 127)
            &Sprite.monogram[char - 32]
        else
            &Sprite.monogram[127 - 32 + 1];

        c.draw_sprite(sprite, cur_x, y);
        cur_x += dx + sprite.w;
    }
}

const ImmediateCanvas = struct {
    surf: Surface,

    const Self = @This();

    pub fn init(provided_surf: Surface) Self {
        return .{ .surf = provided_surf };
    }

    pub fn begin_frame(self: *Self) void {
        _ = self;
    }

    pub fn draw_rect(self: *Self, rect: Rect, color: RGBA) void {
        const dest_rect = Rect.intersect(Rect.from_wh(self.surf.w, self.surf.h), rect);
        draw_rect_to_surface(self.surf, dest_rect, color);
    }

    pub fn draw_sprite(self: *Self, sprite: *const Sprite, x: i32, y: i32) void {
        const dest_rect = Rect.intersect(
            Rect.from_wh(self.surf.w, self.surf.h),
            Rect.from_wh(sprite.w, sprite.h).offset(x, y),
        );
        draw_sprite_to_surface(self.surf, dest_rect, sprite, dest_rect.x - x, dest_rect.y - y);
    }

    pub fn end_frame(self: *Self) void {
        _ = self;
    }
};

const CachedCanvas = struct {
    surf: Surface,

    cur_frame_ops: std.BoundedArray(DrawOp, 256),

    prev_frame_ops: std.BoundedArray(DrawOp, 256),
    prev_frame_grid: [250]std.BoundedArray(u8, 64),

    const Self = @This();

    const cell_wh = 128;

    const DrawOp = union(enum) {
        rect: struct {
            rect: Rect,
            color: RGBA,
        },
        sprite: struct {
            sprite: *const Sprite,
            x: i32,
            y: i32,
        },
    };

    pub fn init(provided_surf: Surface) CachedCanvas {
        return .{
            .surf = provided_surf,
            .cur_frame_ops = std.BoundedArray(DrawOp, 256){},
            .prev_frame_ops = std.BoundedArray(DrawOp, 256){},
            .prev_frame_grid = .{std.BoundedArray(u8, 64){}} ** 250,
        };
    }

    pub fn begin_frame(self: *Self) void {
        _ = self;
    }

    pub fn draw_rect(self: *Self, rect: Rect, color: RGBA) void {
        self.cur_frame_ops.appendAssumeCapacity(.{ .rect = .{ .rect = rect, .color = color } });
    }

    pub fn draw_sprite(self: *Self, sprite: *const Sprite, x: i32, y: i32) void {
        self.cur_frame_ops.appendAssumeCapacity(.{ .sprite = .{ .x = x, .y = y, .sprite = sprite } });
    }

    fn draw_op(self: *Self, op: DrawOp, cell_x: i32, cell_y: i32) void {
        const cell_rect: Rect = .{
            .x = cell_x * cell_wh,
            .y = cell_y * cell_wh,
            .w = @min(self.surf.w - cell_x * cell_wh, cell_wh),
            .h = @min(self.surf.h - cell_y * cell_wh, cell_wh),
        };
        switch (op) {
            .rect => |rect_op| {
                const dest_rect = Rect.intersect(cell_rect, rect_op.rect);
                draw_rect_to_surface(self.surf, dest_rect, rect_op.color);
            },
            .sprite => |sprite_op| {
                const dest_rect = Rect.intersect(
                    cell_rect,
                    Rect.from_wh(sprite_op.sprite.w, sprite_op.sprite.h).offset(sprite_op.x, sprite_op.y),
                );
                draw_sprite_to_surface(
                    self.surf,
                    dest_rect,
                    sprite_op.sprite,
                    dest_rect.x - sprite_op.x,
                    dest_rect.y - sprite_op.y,
                );
            },
        }
    }

    pub fn end_frame(self: *Self) void {
        const grid_w = std.math.divCeil(i32, self.surf.w, cell_wh) catch unreachable;
        const grid_h = std.math.divCeil(i32, self.surf.h, cell_wh) catch unreachable;

        var grid: [250]std.BoundedArray(u8, 64) = .{std.BoundedArray(u8, 64){}} ** 250;
        for (self.cur_frame_ops.slice(), 0..) |op, i| {
            const dirty_rect: Rect = switch (op) {
                .rect => |rect_op| rect_op.rect,
                .sprite => |sprite_op| .{ .x = sprite_op.x, .y = sprite_op.y, .w = sprite_op.sprite.w, .h = sprite_op.sprite.h },
            };
            const x1 = @divTrunc(dirty_rect.x, cell_wh);
            const y1 = @divTrunc(dirty_rect.y, cell_wh);
            const x2 = @divTrunc(dirty_rect.x + dirty_rect.w, cell_wh);
            const y2 = @divTrunc(dirty_rect.y + dirty_rect.h, cell_wh);
            var x = x1;
            while (x <= x2) : (x += 1) {
                var y = y1;
                while (y <= y2) : (y += 1) {
                    grid[@intCast(y * grid_w + x)].appendAssumeCapacity(@intCast(i));
                }
            }
        }

        var cell_y: i32 = 0;
        while (cell_y < grid_h) : (cell_y += 1) {
            var cell_x: i32 = 0;
            while (cell_x < grid_w) : (cell_x += 1) {
                const t: usize = @intCast(cell_y * grid_w + cell_x);
                const new_ops_id = grid[t].slice();
                const old_ops_id = self.prev_frame_grid[t].slice();

                const eql = is_eql: {
                    if (new_ops_id.len != old_ops_id.len) break :is_eql false;
                    for (new_ops_id, old_ops_id) |new_id, old_id| {
                        if (!std.meta.eql(self.cur_frame_ops.get(new_id), self.prev_frame_ops.get(old_id))) {
                            break :is_eql false;
                        }
                    }
                    break :is_eql true;
                };

                if (!eql) {
                    for (new_ops_id) |id| {
                        self.draw_op(self.cur_frame_ops.get(id), cell_x, cell_y);
                    }
                }
                self.prev_frame_grid[t] = grid[t];
            }
        }

        self.prev_frame_ops = self.cur_frame_ops;
        self.cur_frame_ops = std.BoundedArray(DrawOp, 256){};
    }
};
