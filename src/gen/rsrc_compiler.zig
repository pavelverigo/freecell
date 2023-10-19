const std = @import("std");
const c = @cImport({
    @cDefine("STBI_ONLY_PNG", "");
    @cInclude("stb_image.h");
});

pub fn main() !void {
    var data_info_file = try std.fs.cwd().createFile("out/sprites.info", .{});
    var data_file = try std.fs.cwd().createFile("out/sprites.data", .{});

    {
        var suits = [_][]const u8{ "clubs", "diamonds", "hearts", "spades" };
        var cards = [_][]const u8{ "a", "2", "3", "4", "5", "6", "7", "8", "9", "10", "j", "q", "k" };
        var suits_filepath = [_][*c]const u8{ "rsrc/clubs-88x124.png", "rsrc/diamonds-88x124.png", "rsrc/hearts-88x124.png", "rsrc/spades-88x124.png" };

        for (suits, suits_filepath) |suit, filepath| {
            std.debug.print("for {s} {s}\n", .{ suit, filepath });

            var tmp_w: i32 = -1;
            var tmp_h: i32 = -1;
            var image_n: i32 = -1;
            var image_ptr = c.stbi_load(filepath, &tmp_w, &tmp_h, &image_n, 4) orelse @panic("image load failure");

            var image_w: usize = @intCast(tmp_w);
            var image_h: usize = @intCast(tmp_h);

            var image_data = image_ptr[0 .. 4 * image_w * image_h];
            defer c.stbi_image_free(image_ptr);

            std.debug.print("image loaded: w: {}, h: {}, n: {}\n", .{ image_w, image_h, image_n });

            const card_w = 88;
            const card_h = 124;

            if (card_w * 13 != image_w or card_h != image_h) {
                @panic("loaded image unexpected size");
            }

            for (0..13, cards) |i, card| {
                const x = i * card_w;
                const y = 0;

                var buf: [256]u8 = undefined;
                const out = try std.fmt.bufPrint(&buf, "{s}_{s} {} {}\n", .{ suit, card, card_w, card_h });
                try data_info_file.writeAll(out);

                try copyToFile(data_file, image_data, image_w, image_h, x, y, card_w, card_h);
            }
        }
    }

    {
        var tmp_w: i32 = -1;
        var tmp_h: i32 = -1;
        var image_n: i32 = -1;
        var image_ptr = c.stbi_load("rsrc/cursor-28x38.png", &tmp_w, &tmp_h, &image_n, 4) orelse @panic("image load failure");

        var image_w: usize = @intCast(tmp_w);
        var image_h: usize = @intCast(tmp_h);

        var image_data = image_ptr[0 .. 4 * image_w * image_h];
        defer c.stbi_image_free(image_ptr);

        std.debug.print("image loaded: w: {}, h: {}, n: {}\n", .{ image_w, image_h, image_n });

        const cursor_w = 28;
        const cursor_h = 38;

        if (cursor_w != image_w or cursor_h != image_h) {
            @panic("loaded image unexpected size");
        }

        var buf: [256]u8 = undefined;
        const out = try std.fmt.bufPrint(&buf, "cursor {} {}\n", .{ cursor_w, cursor_h });
        try data_info_file.writeAll(out);
        try copyToFile(data_file, image_data, image_w, image_h, 0, 0, cursor_w, cursor_h);
    }
}

fn copyToFile(file: std.fs.File, data: []u8, data_w: usize, data_h: usize, x: usize, y: usize, w: usize, h: usize) !void {
    _ = data_h;

    var offset_y: usize = 0;
    while (offset_y < h) {
        var offset_x: usize = 0;
        while (offset_x < w) {
            const i = 4 * ((y + offset_y) * data_w + x + offset_x);

            // const r = data[i];
            // const g = data[i + 1];
            // const b = data[i + 2];
            // const a = data[i + 3];

            try file.writeAll(data[i .. i + 4]);

            offset_x += 1;
        }

        offset_y += 1;
    }
}
