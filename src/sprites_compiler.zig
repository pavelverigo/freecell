const std = @import("std");
const c = @cImport({
    @cDefine("STBI_ONLY_PNG", "");
    @cInclude("stb_image.h");
});

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try std.process.argsAlloc(arena);

    if (args.len != 3) fatal("wrong number of arguments", .{});

    const zig_file_path = args[1];
    var zig_file = std.fs.cwd().createFile(zig_file_path, .{}) catch |err| {
        fatal("unable to open '{s}': {s}", .{ zig_file_path, @errorName(err) });
    };
    defer zig_file.close();
    const zig_file_writer = zig_file.writer();

    const data_file_path = args[2];
    var data_file = std.fs.cwd().createFile(data_file_path, .{}) catch |err| {
        fatal("unable to open '{s}': {s}", .{ data_file_path, @errorName(err) });
    };
    defer data_file.close();
    const data_file_writer = data_file.writer();

    try zig_file_writer.writeAll(
        \\const std = @import("std");
        \\
        \\const Sprite = @This();
        \\
        \\w: i32,
        \\h: i32,
        \\/// RGBA
        \\pixels: []const u32,
        \\
        \\const embed_data_align_tmp align(4) = @embedFile("sprites_data").*;
        \\const embed_data = std.mem.bytesAsSlice(u32, &embed_data_align_tmp);
        \\
        \\
    );

    var embeder: SpriteEmbeder = .{ .source_writer = zig_file_writer.any(), .data_writer = data_file_writer.any() };

    {
        const suits = [_][]const u8{ "clubs", "diamonds", "hearts", "spades" };
        const cards = [_][]const u8{ "a", "2", "3", "4", "5", "6", "7", "8", "9", "10", "j", "q", "k" };
        const card_w = 88;
        const card_h = 124;
        const suits_filepath = [_][*c]const u8{ "sprites/clubs-88x124.png", "sprites/diamonds-88x124.png", "sprites/hearts-88x124.png", "sprites/spades-88x124.png" };

        for (suits, suits_filepath) |suit, filepath| {
            var image = STBImage.load(filepath);
            defer image.deinit();
            std.debug.assert(image.w == card_w * 13 and image.h == card_h);

            for (0..13, cards) |i, card| {
                const x = i * card_w;
                const y = 0;
                const name = try std.fmt.allocPrint(arena, "{s}_{s}", .{ suit, card });
                try embeder.embed_cropped_image(name, image, x, y, card_w, card_h);
            }
        }

        try zig_file_writer.print("\n", .{});
    }

    { // aux
        const suits = [_][]const u8{ "spades", "hearts", "diamonds", "clubs" };
        const card_w = 88;
        const card_h = 124;

        var image = STBImage.load("sprites/aux-88x124.png");
        defer image.deinit();
        std.debug.assert(image.w == card_w * 4 and image.h == card_h);

        for (suits, 0..) |suit, i| {
            const x = i * card_w;
            const y = 0;
            const name = try std.fmt.allocPrint(arena, "{s}_foundation", .{suit});
            try embeder.embed_cropped_image(name, image, x, y, card_w, card_h);
        }

        try zig_file_writer.print("\n", .{});
    }

    {
        const text_w = 10;
        const text_h = 22;
        const char_cnt = (127 - 32 + 1) + 1;

        var image = STBImage.load("sprites/monogram-10x22.png");
        defer image.deinit();
        std.debug.assert(image.w == text_w * char_cnt and image.h == text_h);

        try zig_file_writer.print("pub const monogram: [{}]Sprite = .{{\n", .{char_cnt});
        for (0..char_cnt) |i| {
            const crop_x = i * text_w;
            const crop_y = 0;
            const crop_w = text_w;
            const crop_h = text_h;
            const source_image = image;

            try zig_file_writer.print(
                \\    .{{ .w = {}, .h = {}, .pixels = embed_data[{}..][0..{}] }},
                \\
            , .{ text_w, text_h, embeder.embed_data_offset, crop_w * crop_h });
            embeder.embed_data_offset += crop_w * crop_h;

            for (0..crop_h) |offset_y| {
                const start = 4 * ((crop_y + offset_y) * source_image.w + crop_x);
                try data_file_writer.writeAll(source_image.data[start..][0 .. 4 * crop_w]);
            }
        }
        try zig_file_writer.print("}};\n", .{});
        try zig_file_writer.print("\n", .{});
    }

    {
        const cursor_w = 28;
        const cursor_h = 38;

        var image = STBImage.load("sprites/cursor-28x38.png");
        defer image.deinit();
        std.debug.assert(image.w == cursor_w and image.h == cursor_h);

        try embeder.embed_cropped_image("cursor", image, 0, 0, cursor_w, cursor_h);

        try zig_file_writer.print("\n", .{});
    }
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}

const SpriteEmbeder = struct {
    source_writer: std.io.AnyWriter,
    data_writer: std.io.AnyWriter,
    embed_data_offset: usize = 0,

    const Self = @This();

    fn embed_cropped_image(self: *Self, name: []const u8, source_image: STBImage, crop_x: usize, crop_y: usize, crop_w: usize, crop_h: usize) !void {
        try self.source_writer.print(
            \\pub const {s}: Sprite = .{{ .w = {}, .h = {}, .pixels = embed_data[{}..][0..{}] }};
            \\
        , .{ name, crop_w, crop_h, self.embed_data_offset, crop_w * crop_h });
        self.embed_data_offset += crop_w * crop_h;

        for (0..crop_h) |offset_y| {
            const start = 4 * ((crop_y + offset_y) * source_image.w + crop_x);
            try self.data_writer.writeAll(source_image.data[start..][0 .. 4 * crop_w]);
        }
    }
};

const STBImage = struct {
    c_ptr: [*c]u8,
    data: []u8,
    w: usize,
    h: usize,

    fn load(filepath: [*c]const u8) STBImage {
        var image: STBImage = undefined;
        var tmp_w: i32 = undefined;
        var tmp_h: i32 = undefined;
        image.c_ptr = c.stbi_load(filepath, &tmp_w, &tmp_h, null, 4) orelse {
            fatal("image load failure '{s}'", .{filepath});
        };
        image.w = @intCast(tmp_w);
        image.h = @intCast(tmp_h);
        image.data = image.c_ptr[0 .. 4 * image.w * image.h];
        return image;
    }

    fn deinit(image: *STBImage) void {
        c.stbi_image_free(image.c_ptr);
        image.* = undefined;
    }
};
