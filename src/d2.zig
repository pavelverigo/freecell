const std = @import("std");
const wasm = @import("wasm.zig");

// TODO TODO TODO
pub fn sliceCast(comptime T: type, buffer: []const u8) []T {
    // TODO count obtained by division abort on not equal lenght (panic)
    const count = @divTrunc(buffer.len, @sizeOf(T));
    return @as([*]T, @constCast(@alignCast(@ptrCast(buffer.ptr))))[0..count];
}

pub const sprites_data = @embedFile("gen/sprites.data");

pub const RGBA = packed struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub const BLACK: RGBA = .{ .r = 0x00, .g = 0x00, .b = 0x00, .a = 0xFF };
    pub const WHITE: RGBA = .{ .r = 0xFF, .g = 0xFF, .b = 0xFF, .a = 0xFF };
};

pub const Image = struct {
    data: []RGBA,
    w: i32,
    h: i32,
};

fn imageDrawImage(dest: Image, dx: i32, dy: i32, src: Image, sx: i32, sy: i32, w: i32, h: i32, dark_blend: ?f32) void {
    const start_offset_x = @max(-dx, -sx, 0);
    const end_offset_x = @max(@min(dest.w - dx, src.w - sx, w), 0);

    const start_offset_y = @max(-dy, -sy, 0);
    const end_offset_y = @max(@min(dest.h - dy, src.h - sy, h), 0);

    var offset_y = start_offset_y;
    while (offset_y < end_offset_y) {
        var offset_x = start_offset_x;
        while (offset_x < end_offset_x) {
            const i: usize = @intCast(dest.w * (dy + offset_y) + dx + offset_x);
            const j: usize = @intCast(src.w * (sy + offset_y) + sx + offset_x);

            // TODO better alpha handling
            if (src.data[j].a == 0xFF) {
                if (dark_blend) |blend| {
                    const r: u8 = @intFromFloat(@as(f32, @floatFromInt(src.data[j].r)) / blend);
                    const g: u8 = @intFromFloat(@as(f32, @floatFromInt(src.data[j].g)) / blend);
                    const b: u8 = @intFromFloat(@as(f32, @floatFromInt(src.data[j].b)) / blend);

                    dest.data[i] = .{ .r = r, .g = g, .b = b, .a = src.data[j].a };
                } else {
                    dest.data[i] = src.data[j];
                }
            }

            offset_x += 1;
        }
        offset_y += 1;
    }
}

fn imageDrawImageGrid(dest: Image, dx: i32, dy: i32, src: Image, sx: i32, sy: i32, w: i32, h: i32, dark_blend: ?f32, grid_x: i32, grid_y: i32, comptime grid_wh: i32) void {
    const start_offset_x = @max(-dx, -sx, 0, grid_x - dx);
    const end_offset_x = @max(@min(dest.w - dx, src.w - sx, w, grid_x + grid_wh - dx), 0);

    const start_offset_y = @max(-dy, -sy, 0, grid_y - dy);
    const end_offset_y = @max(@min(dest.h - dy, src.h - sy, h, grid_y + grid_wh - dy), 0);

    var offset_y = start_offset_y;
    while (offset_y < end_offset_y) {
        var offset_x = start_offset_x;
        while (offset_x < end_offset_x) {
            const i: usize = @intCast(dest.w * (dy + offset_y) + dx + offset_x);
            const j: usize = @intCast(src.w * (sy + offset_y) + sx + offset_x);

            // TODO better alpha handling
            if (src.data[j].a == 0xFF) {
                if (dark_blend) |blend| {
                    const r: u8 = @intFromFloat(@as(f32, @floatFromInt(src.data[j].r)) / blend);
                    const g: u8 = @intFromFloat(@as(f32, @floatFromInt(src.data[j].g)) / blend);
                    const b: u8 = @intFromFloat(@as(f32, @floatFromInt(src.data[j].b)) / blend);

                    dest.data[i] = .{ .r = r, .g = g, .b = b, .a = src.data[j].a };
                } else {
                    dest.data[i] = src.data[j];
                }
            }

            offset_x += 1;
        }
        offset_y += 1;
    }
}

fn imageDrawRect(dest: Image, x: i32, y: i32, w: i32, h: i32, color: RGBA) void {
    const start_offset_x = @max(-x, 0);
    const end_offset_x = @max(@min(dest.w - x, w), 0);

    const start_offset_y = @max(-y, 0);
    const end_offset_y = @max(@min(dest.h - y, h), 0);

    var offset_y = start_offset_y;
    while (offset_y < end_offset_y) {
        var offset_x = start_offset_x;
        while (offset_x < end_offset_x) {
            const i: usize = @intCast(dest.w * (y + offset_y) + x + offset_x);

            // TODO better alpha handling
            dest.data[i] = color;

            offset_x += 1;
        }
        offset_y += 1;
    }
}

fn imageDrawRectGrid(dest: Image, x: i32, y: i32, w: i32, h: i32, color: RGBA, grid_x: i32, grid_y: i32, comptime grid_wh: i32) void {
    const start_offset_x = @max(-x, 0, grid_x - x);
    const end_offset_x = @max(@min(dest.w - x, w, grid_x + grid_wh - x), 0);

    const start_offset_y = @max(-y, 0, grid_y - y);
    const end_offset_y = @max(@min(dest.h - y, h, grid_y + grid_wh - y), 0);

    var offset_y = start_offset_y;
    while (offset_y < end_offset_y) {
        var offset_x = start_offset_x;
        while (offset_x < end_offset_x) {
            const i: usize = @intCast(dest.w * (y + offset_y) + x + offset_x);

            // TODO better alpha handling
            dest.data[i] = color;

            offset_x += 1;
        }
        offset_y += 1;
    }
}

const genSpritesData = blk: {
    @setEvalBranchQuota(20000);

    const sprites_info = @embedFile("gen/sprites.info");

    var fields: [128]std.builtin.Type.EnumField = undefined;

    const ImageInfo = struct {
        w: i32,
        h: i32,
    };
    var image_info: [128]ImageInfo = undefined;

    const sprites_len = parse: {
        var i: usize = 0;
        var it = std.mem.tokenizeAny(u8, sprites_info, " \n");

        while (true) {
            const name = it.next() orelse break;
            const w_str = it.next().?;
            const w = std.fmt.parseInt(i32, w_str, 10) catch unreachable;
            const h_str = it.next().?;
            const h = std.fmt.parseInt(i32, h_str, 10) catch unreachable;

            fields[i] = .{
                .name = name,
                .value = i,
            };

            image_info[i] = .{
                .w = w,
                .h = h,
            };

            i += 1;
        }

        break :parse i;
    };

    const SpritesEnum = @Type(.{
        .Enum = .{
            .tag_type = u32,
            .fields = fields[0..sprites_len],
            .decls = &.{},
            .is_exhaustive = true,
        },
    });

    var sprites_image_tmp = std.EnumArray(SpritesEnum, Image).initUndefined();

    {
        var offset: usize = 0;
        for (image_info[0..sprites_len], 0..) |info, i| {
            const len: usize = @intCast(info.w * info.h);
            sprites_image_tmp.set(
                @enumFromInt(i),
                .{
                    .data = sliceCast(RGBA, sprites_data[4 * offset .. 4 * offset + 4 * len]),
                    .w = info.w,
                    .h = info.h,
                },
            );
            offset += len;
        }
    }

    break :blk .{
        SpritesEnum,
        sprites_image_tmp,
    };
};

pub const Sprites = genSpritesData[0];
const sprites_image = genSpritesData[1];

pub const Canvas = struct {
    backed_image: Image,

    pub fn init(image: Image) Canvas {
        return .{
            .backed_image = image,
        };
    }

    pub fn resize(self: *Canvas, image: Image) void {
        self.backed_image = image;
    }

    pub fn drawColor(self: *Canvas, color: RGBA) void {
        self.drawRect(0, 0, self.backed_image.w, self.backed_image.h, color);
    }

    pub fn drawRect(self: *Canvas, x: i32, y: i32, w: i32, h: i32, color: RGBA) void {
        imageDrawRect(self.backed_image, x, y, w, h, color);
    }

    pub fn drawSprite(self: *Canvas, x: i32, y: i32, sprite: Sprites, dark_blend: ?f32) void {
        var sprite_image = sprites_image.get(sprite);
        imageDrawImage(self.backed_image, x, y, sprite_image, 0, 0, sprite_image.w, sprite_image.h, dark_blend);
    }

    pub fn width(self: *Canvas) i32 {
        return self.backed_image.w;
    }

    pub fn height(self: *Canvas) i32 {
        return self.backed_image.h;
    }

    pub fn finalize(self: *Canvas) void {
        _ = self;
    }
};

pub const CachedCanvas = struct {
    backed_image: Image,
    cnt: usize = 0,

    ops: std.BoundedArray(Op, 256),
    old_ops: std.BoundedArray(Op, 256),

    op_grid: std.BoundedArray(std.BoundedArray(u8, 64), grid_size),

    const grid_wh = 128;
    const grid_size = 512;

    const Op = union(enum) {
        rect: RectOp,
        sprite: SpriteOp,

        // comptime {
        //     @compileLog(@bitSizeOf(@This()));
        // }

        const RectOp = struct {
            x: i16,
            y: i16,
            w: i16,
            h: i16,
            color: RGBA,
        };

        const SpriteOp = struct {
            x: i16,
            y: i16,
            dark_blend: ?f32,
            sprite: Sprites,
        };
    };

    pub fn init(image: Image) CachedCanvas {
        return .{
            .backed_image = image,
            .ops = std.BoundedArray(Op, 256).init(0) catch undefined,
            .old_ops = std.BoundedArray(Op, 256).init(0) catch undefined,
            .op_grid = std.BoundedArray(std.BoundedArray(u8, 64), grid_size).init(0) catch undefined,
        };
    }

    pub fn resize(self: *CachedCanvas, image: Image) void {
        self.backed_image = image;
        self.old_ops = std.BoundedArray(Op, 256).init(0) catch undefined;
        self.op_grid = std.BoundedArray(std.BoundedArray(u8, 64), grid_size).init(0) catch undefined;
    }

    pub fn drawColor(self: *CachedCanvas, color: RGBA) void {
        self.ops.append(.{ .rect = .{ .x = 0, .y = 0, .w = @intCast(self.backed_image.w), .h = @intCast(self.backed_image.h), .color = color } }) catch unreachable;
    }

    pub fn drawRect(self: *CachedCanvas, x: i32, y: i32, w: i32, h: i32, color: RGBA) void {
        self.ops.append(.{ .rect = .{ .x = @intCast(x), .y = @intCast(y), .w = @intCast(w), .h = @intCast(h), .color = color } }) catch unreachable;
    }

    pub fn drawSprite(self: *CachedCanvas, x: i32, y: i32, sprite: Sprites, dark_blend: ?f32) void {
        self.ops.append(.{ .sprite = .{ .x = @intCast(x), .y = @intCast(y), .sprite = sprite, .dark_blend = dark_blend } }) catch unreachable;
    }

    pub fn width(self: *CachedCanvas) i32 {
        return self.backed_image.w;
    }

    pub fn height(self: *CachedCanvas) i32 {
        return self.backed_image.h;
    }

    fn regionOp(grid: *std.BoundedArray(std.BoundedArray(u8, 64), grid_size), grid_w: i32, grid_h: i32, x: i32, y: i32, w: i32, h: i32, i: usize) void {
        _ = grid_h;
        const x1 = @divTrunc(x, grid_wh);
        const y1 = @divTrunc(y, grid_wh);
        const x2 = @divTrunc(x + w, grid_wh);
        const y2 = @divTrunc(y + h, grid_wh);
        var xc = x1;
        while (xc <= x2) {
            var yc = y1;
            while (yc <= y2) {
                grid.buffer[@intCast(yc * grid_w + xc)].append(@intCast(i)) catch unreachable;
                yc += 1;
            }
            xc += 1;
        }
    }

    fn drawOp(self: *CachedCanvas, op: Op, grid_x: i32, grid_y: i32) void {
        switch (op) {
            .rect => |rect| {
                imageDrawRectGrid(self.backed_image, rect.x, rect.y, rect.w, rect.h, rect.color, grid_x, grid_y, grid_wh);
            },
            .sprite => |sprite| {
                var sprite_image = sprites_image.get(sprite.sprite);
                imageDrawImageGrid(self.backed_image, sprite.x, sprite.y, sprite_image, 0, 0, sprite_image.w, sprite_image.h, sprite.dark_blend, grid_x, grid_y, grid_wh);
            },
        }
    }

    pub fn finalize(self: *CachedCanvas) void {
        const grid_w = std.math.divCeil(i32, self.backed_image.w, grid_wh) catch unreachable;
        const grid_h = std.math.divCeil(i32, self.backed_image.h, grid_wh) catch unreachable;

        var grid = std.BoundedArray(std.BoundedArray(u8, 64), grid_size).init(@intCast(grid_w * grid_h)) catch unreachable;

        for (self.ops.slice(), 0..) |op1, i| {
            switch (op1) {
                .rect => |op| {
                    regionOp(&grid, grid_w, grid_h, op.x, op.y, op.w, op.h, i);
                },
                .sprite => |op| {
                    var sprite_image = sprites_image.get(op.sprite);
                    regionOp(&grid, grid_w, grid_h, op.x, op.y, sprite_image.w, sprite_image.h, i);
                },
            }
        }

        {
            var y: i32 = 0;
            while (y < grid_h) {
                var x: i32 = 0;
                while (x < grid_w) {
                    const t: usize = @intCast(y * grid_w + x);
                    const grid_x: i32 = grid_wh * x;
                    const grid_y: i32 = grid_wh * y;
                    const new = grid.buffer[t].slice();

                    if (self.op_grid.len == grid.len) {
                        const old = self.op_grid.buffer[t].slice();

                        const eql = blk: {
                            if (new.len != old.len) break :blk false;
                            for (new, old) |id1, id2| {
                                if (!std.meta.eql(self.ops.get(id1), self.old_ops.get(id2))) break :blk false;
                            }
                            break :blk true;
                        };

                        if (!eql) {
                            for (new) |id| {
                                self.drawOp(self.ops.get(id), grid_x, grid_y);
                            }
                        }
                        self.op_grid.buffer[t] = grid.buffer[t];
                    } else {
                        for (new) |id| {
                            self.drawOp(self.ops.get(id), grid_x, grid_y);
                        }
                    }

                    x += 1;
                }
                y += 1;
            }
        }

        if (self.op_grid.len != grid.len) {
            self.op_grid.resize(0) catch unreachable;
            for (grid.slice()) |cell| {
                self.op_grid.append(cell) catch unreachable;
            }
        }

        self.old_ops = self.ops;
        self.ops.resize(0) catch unreachable;
    }
};
