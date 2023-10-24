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

    { // aux
        var suits = [_][]const u8{ "spades", "hearts", "diamonds", "clubs" };

        var tmp_w: i32 = -1;
        var tmp_h: i32 = -1;
        var image_n: i32 = -1;
        var image_ptr = c.stbi_load("rsrc/aux-88x124.png", &tmp_w, &tmp_h, &image_n, 4) orelse @panic("image load failure");

        var image_w: usize = @intCast(tmp_w);
        var image_h: usize = @intCast(tmp_h);

        std.debug.print("image loaded: w: {}, h: {}, n: {}\n", .{ image_w, image_h, image_n });

        var image_data = image_ptr[0 .. 4 * image_w * image_h];
        defer c.stbi_image_free(image_ptr);

        const card_w = 88;
        const card_h = 124;

        if (card_w * 4 != image_w or card_h != image_h) {
            @panic("loaded image unexpected size");
        }

        for (suits, 0..) |suit, i| {
            const x = i * card_w;
            const y = 0;

            var buf: [256]u8 = undefined;
            const out = try std.fmt.bufPrint(&buf, "{s}_foundation {} {}\n", .{ suit, card_w, card_h });
            try data_info_file.writeAll(out);

            try copyToFile(data_file, image_data, image_w, image_h, x, y, card_w, card_h);
        }
    }

    { // aux
        var ui_names = [_][]const u8{
            "fullscreen_on",
            "fullscreen_on_hover",
            "fullscreen_off",
            "fullscreen_off_hover",
            "new_game",
            "new_game_hover",
            "restart_game",
            "restart_game_hover",
            "highlight_on",
            "highlight_off",
            "highlight_on_hover",
            "highlight_off_hover",
        };
        const ui_width = [_]usize{ 50, 50, 50, 50, 125, 125, 165, 165, 250, 250, 250, 250 };
        const ui_width_sum = comptime blk: {
            var tmp = 0;
            for (ui_width) |w| tmp += w;
            break :blk tmp;
        };
        const ui_height = 50;

        var tmp_w: i32 = -1;
        var tmp_h: i32 = -1;
        var image_n: i32 = -1;
        var image_ptr = c.stbi_load("rsrc/ui-height50.png", &tmp_w, &tmp_h, &image_n, 4) orelse @panic("image load failure");

        var image_w: usize = @intCast(tmp_w);
        var image_h: usize = @intCast(tmp_h);

        std.debug.print("image loaded: w: {}, h: {}, n: {}\n", .{ image_w, image_h, image_n });

        var image_data = image_ptr[0 .. 4 * image_w * image_h];
        defer c.stbi_image_free(image_ptr);

        if (ui_width_sum != image_w or ui_height != image_h) {
            @panic("loaded image unexpected size");
        }

        var x: usize = 0;
        for (ui_names, ui_width) |name, w| {
            const y = 0;

            var buf: [256]u8 = undefined;
            const out = try std.fmt.bufPrint(&buf, "{s} {} {}\n", .{ name, w, ui_height });
            try data_info_file.writeAll(out);

            try copyToFile(data_file, image_data, image_w, image_h, x, y, w, ui_height);

            x += w;
        }
    }

    { // aux
        const text_w = 32;
        const text_h = 32;

        var tmp_w: i32 = -1;
        var tmp_h: i32 = -1;
        var image_n: i32 = -1;
        var image_ptr = c.stbi_load("rsrc/text-32x32.png", &tmp_w, &tmp_h, &image_n, 4) orelse @panic("image load failure");

        var image_w: usize = @intCast(tmp_w);
        var image_h: usize = @intCast(tmp_h);

        std.debug.print("image loaded: w: {}, h: {}, n: {}\n", .{ image_w, image_h, image_n });

        var image_data = image_ptr[0 .. 4 * image_w * image_h];
        defer c.stbi_image_free(image_ptr);

        if (text_w != image_w or text_h * 26 != image_h) {
            @panic("loaded image unexpected size");
        }

        for ('a'..('z' + 1), 0..) |letter, i| {
            const x = 0;
            const y = i * text_h;

            var buf: [256]u8 = undefined;
            const out = try std.fmt.bufPrint(&buf, "text_{s} {} {}\n", .{ [1]u8{@intCast(letter)}, text_w, text_w });
            try data_info_file.writeAll(out);

            try copyToFile(data_file, image_data, image_w, image_h, x, y, text_w, text_w);
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
