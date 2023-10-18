const std = @import("std");
const c = @cImport({
    @cDefine("STBI_ONLY_PNG", "");
    @cInclude("stb_image.h");
});

pub fn main() !void {
    var data_info_file = try std.fs.cwd().createFile("out/sprites.info", .{});
    var data_file = try std.fs.cwd().createFile("out/sprites.data", .{});

    var pips = [_][]const u8{ "clubs", "diamonds", "hearts", "spades" };
    var cards = [_][]const u8{ "a", "2", "3", "4", "5", "6", "7", "8", "9", "10", "j", "q", "k" };
    var pips_filepath = [_][*c]const u8{ "rsrc/Clubs-88x124.png", "rsrc/Diamonds-88x124.png", "rsrc/Hearts-88x124.png", "rsrc/Spades-88x124.png" };

    for (pips, pips_filepath) |pip, filepath| {
        std.debug.print("for {s} {s}\n", .{ pip, filepath });

        var tmp_w: i32 = -1;
        var tmp_h: i32 = -1;
        var image_n: i32 = -1;
        var image_ptr = c.stbi_load(filepath, &tmp_w, &tmp_h, &image_n, 4) orelse @panic("image load failure");

        var image_w: usize = @intCast(tmp_w);
        var image_h: usize = @intCast(tmp_h);

        var image_data = image_ptr[0 .. 4 * image_w * image_h];
        defer c.stbi_image_free(image_ptr);

        std.debug.print("Image load: w: {}, h: {}, n: {}\n", .{ image_w, image_h, image_n });

        const card_w = 88;
        const card_h = 124;

        if (card_w * 5 != image_w or card_h * 3 != image_h) {
            @panic("loaded image unexpected size");
        }

        const helper = struct {
            pub fn copyToFile(file: std.fs.File, data: []u8, data_w: usize, data_h: usize, x: usize, y: usize, w: usize, h: usize) !void {
                _ = data_h;

                var offset_y: usize = 0;
                while (offset_y < h) {
                    var offset_x: usize = 0;
                    while (offset_x < w) {
                        const i = 4 * ((y + offset_y) * data_w + x + offset_x);

                        const r = data[i];
                        const g = data[i + 1];
                        const b = data[i + 2];
                        const a = data[i + 3];

                        if (r == 0 and g == 128 and b == 128 and a == 255) {
                            try file.writeAll(&.{ 0, 0, 0, 0 });
                        } else {
                            try file.writeAll(data[i .. i + 4]);
                        }

                        offset_x += 1;
                    }

                    offset_y += 1;
                }
            }
        };

        for (0..13, cards) |i, card| {
            const row = @divTrunc(i, 5);
            const column = @rem(i, 5);

            // std.debug.print("row {} column {}\n", .{ row, column });

            const x = column * card_w;
            const y = row * card_h;

            var buf: [256]u8 = undefined;
            const out = try std.fmt.bufPrint(&buf, "{s}_{s} {} {}\n", .{ pip, card, card_w, card_h });
            try data_info_file.writeAll(out);

            try helper.copyToFile(data_file, image_data, image_w, image_h, x, y, card_w, card_h);
        }
    }
}
