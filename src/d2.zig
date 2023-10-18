const std = @import("std");

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

fn imageDrawImage(dest: Image, dx: i32, dy: i32, src: Image, sx: i32, sy: i32, w: i32, h: i32) void {
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
                dest.data[i] = src.data[j];
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

const genSpritesData = blk: {
    @setEvalBranchQuota(10000);

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

    pub fn drawColor(self: *Canvas, color: RGBA) void {
        self.drawRect(0, 0, self.backed_image.w, self.backed_image.h, color);
    }

    pub fn drawRect(self: *Canvas, x: i32, y: i32, w: i32, h: i32, color: RGBA) void {
        imageDrawRect(self.backed_image, x, y, w, h, color);
    }

    pub fn drawSprite(self: *Canvas, x: i32, y: i32, sprite: Sprites) void {
        var sprite_image = sprites_image.get(sprite);
        imageDrawImage(self.backed_image, x, y, sprite_image, 0, 0, sprite_image.w, sprite_image.h);
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
