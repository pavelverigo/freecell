const wasm = @import("wasm.zig");
const d2 = @import("d2.zig");
const std = @import("std");

var game: App = undefined;

// Called once
pub fn init(main_image: d2.Image) void {
    game = App.init(main_image);
}

pub fn resize(new_image: d2.Image) void {
    game.resize(new_image);
}

// Called every frame
pub fn frame(mouse_x: i32, mouse_y: i32, mouse_inside: bool, mouse_pressed: bool, time: f32, fps: f32) void {
    game.frame(mouse_x, mouse_y, mouse_inside, mouse_pressed, time, fps);
}

// Fullscreen status changed from outside
pub fn fullscreen_mode(mode: bool) void {
    game.fullscreen_mode(mode);
}

const Card = struct {
    pub const Suit = enum {
        diamonds,
        hearts,
        clubs,
        spades,

        pub fn isBlack(s: Suit) bool {
            return s == .clubs or s == .spades;
        }

        pub fn isRed(s: Suit) bool {
            return s == .diamonds or s == .hearts;
        }

        pub fn isOppositeColor(s1: Suit, s2: Suit) bool {
            return s1.isRed() != s2.isRed();
        }
    };

    pub const Rank = enum {
        a,
        @"2",
        @"3",
        @"4",
        @"5",
        @"6",
        @"7",
        @"8",
        @"9",
        @"10",
        j,
        q,
        k,

        pub fn diff(r1: Rank, r2: Rank) i32 {
            const int1 = @as(i32, @intFromEnum(r1));
            const int2 = @as(i32, @intFromEnum(r2));
            return int1 - int2;
        }
    };

    suit: Suit,
    rank: Rank,
};

fn cardToSprite(card: Card) d2.Sprites {
    switch (card.suit) {
        inline else => |suit| {
            switch (card.rank) {
                inline else => |rank| {
                    const suit_str = @tagName(suit);
                    const rank_str = @tagName(rank);
                    return std.enums.nameCast(d2.Sprites, suit_str ++ "_" ++ rank_str);
                },
            }
        },
    }
}

fn suitToSprite(suit: Card.Suit) d2.Sprites {
    switch (suit) {
        inline else => |s| {
            const suit_str = @tagName(s);
            return std.enums.nameCast(d2.Sprites, suit_str ++ "_foundation");
        },
    }
}

const RectRegion = struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,

    pub fn inside(r: RectRegion, x: i32, y: i32) bool {
        return r.x <= x and x < (r.x + r.w) and r.y <= y and y < (r.y + r.h);
    }

    pub fn intersect(r1: RectRegion, r2: RectRegion) RectRegion {
        const x1 = @max(r1.x, r2.x);
        const y1 = @max(r1.y, r2.y);
        const x2 = @min(r1.x + r1.w, r2.x + r2.w);
        const y2 = @min(r1.y + r1.h, r2.y + r2.h);
        return .{ .x = x1, .y = y1, .w = @max(0, x2 - x1), .h = @max(0, y2 - y1) };
    }

    pub fn isEmpty(r: RectRegion) bool {
        return r.w <= 0 or r.h <= 0;
    }

    pub fn area(r: RectRegion) i64 {
        return r.w * r.h;
    }
};

// Represents basic state of freecell game played, no reference to UI and drawing
const Freecell = struct {
    const CASCADE_CARD_LIMIT = 32; // sane limit for bounded arrays

    open_slots: [4]?Card,
    foundations: std.EnumArray(Card.Suit, ?Card.Rank),
    cascades: [8]std.BoundedArray(Card, CASCADE_CARD_LIMIT),

    pub const CardPos = union(enum) {
        open_slot: u8,
        foundation: u8,
        cascade: struct { u8, u8 },
    };

    pub fn isWin(f: *Freecell) bool {
        for (std.enums.values(Card.Suit)) |suit| {
            if (f.foundations.get(suit) != .k) return false;
        }
        return true;
    }

    fn isAutomove(f: *Freecell, card: Card) bool {
        if (f.foundations.get(card.suit)) |rank| {
            if (card.rank == .@"2") return true;
            if (card.rank.diff(rank) != 1) return false;
            for (std.enums.values(Card.Suit)) |suit| {
                if (card.suit.isOppositeColor(suit)) {
                    if (f.foundations.get(suit)) |op_rank| {
                        if (card.rank.diff(op_rank) > 1) return false;
                    } else {
                        return false;
                    }
                }
            }
            return true;
        } else {
            return card.rank == .a;
        }
    }

    pub fn findFoundationAutomove(f: *Freecell) ?CardPos {
        for (0..4) |i| {
            if (f.open_slots[i]) |card| {
                if (f.isAutomove(card)) return .{ .open_slot = @intCast(i) };
            }
        }
        for (0..8) |i| {
            const cascade = f.cascades[i];
            if (cascade.len > 0 and f.isAutomove(cascade.get(cascade.len - 1))) return .{ .cascade = .{ @intCast(i), @intCast(cascade.len - 1) } };
        }
        return null;
    }

    pub fn isMovable(f: *Freecell, pos: CardPos) bool {
        switch (pos) {
            .open_slot => return true,
            .foundation => return false,
            .cascade => |ij| {
                const i = ij[0];
                const cascade = f.cascades[i];
                var j = ij[1];
                const len: usize = cascade.len;
                var cnt: usize = 1;
                while (j + 1 < len) {
                    const card1 = cascade.get(j);
                    const card2 = cascade.get(j + 1);
                    if (!(card1.suit.isOppositeColor(card2.suit) and card1.rank.diff(card2.rank) == 1)) {
                        return false;
                    }
                    cnt += 1;
                    j += 1;
                }
                const limit = blk: {
                    var n: usize = 1;
                    for (0..8) |k| {
                        if (f.cascades[k].len == 0) n *= 2;
                    }
                    var m: usize = 1;
                    for (0..4) |k| {
                        if (f.open_slots[k] == null) m += 1;
                    }
                    break :blk n * m;
                };
                return cnt <= limit;
            },
        }
    }

    pub fn cardsFromPos(f: *Freecell, pos: CardPos) std.BoundedArray(Card, CASCADE_CARD_LIMIT) {
        var cards = std.BoundedArray(Card, CASCADE_CARD_LIMIT).init(0) catch unreachable;
        switch (pos) {
            .open_slot => |i| {
                cards.append(f.open_slots[i].?) catch unreachable;
            },
            .cascade => |ij| {
                const i = ij[0];
                const cascade = f.cascades[i];
                var j = ij[1];
                const len: usize = cascade.len;
                while (j < len) {
                    cards.append(cascade.get(j)) catch unreachable;
                    j += 1;
                }
            },
            .foundation => unreachable,
        }
        return cards;
    }

    pub fn attemptMove(f: *Freecell, from: CardPos, to: CardPos) bool { // "to" value cascade row meaningless
        const cards = f.cardsFromPos(from);

        switch (to) { // abort
            .open_slot => |i| {
                if (!(f.open_slots[i] == null and cards.len == 1)) return false;
            },
            .foundation => |i| {
                if (cards.len != 1) return false;
                const suit: Card.Suit = @enumFromInt(i);
                const card = cards.get(0);
                if (suit != cards.get(0).suit) return false;
                if (f.foundations.get(suit)) |rank| {
                    if (card.rank.diff(rank) != 1) return false;
                } else {
                    if (card.rank != .a) return false;
                }
            },
            .cascade => |ij| {
                const i = ij[0];
                const cascade = f.cascades[i];
                if (cascade.len > 0) {
                    const card1 = cards.get(0);
                    const card2 = cascade.get(cascade.len - 1);

                    if (!(card1.suit.isOppositeColor(card2.suit) and card1.rank.diff(card2.rank) == -1)) return false;
                }
            },
        }

        switch (from) { // delete
            .open_slot => |i| {
                f.open_slots[i] = null;
            },
            .cascade => |ij| {
                const i = ij[0];
                const j = ij[1];
                f.cascades[i].resize(j) catch unreachable;
            },
            .foundation => unreachable,
        }

        switch (to) { // add
            .open_slot => |i| {
                f.open_slots[i] = cards.get(0);
            },
            .cascade => |ij| {
                const i = ij[0];
                for (cards.slice()) |card| {
                    f.cascades[i].append(card) catch unreachable;
                }
            },
            .foundation => |i| {
                const suit: Card.Suit = @enumFromInt(i);
                const card = cards.get(0);
                f.foundations.set(suit, card.rank);
            },
        }
        return true;
    }

    pub fn init(seed: u64) Freecell {
        var deck = comptime blk: {
            var deck_tmp: [52]Card = undefined;
            var i: usize = 0;
            for (std.enums.values(Card.Suit)) |suit| {
                for (std.enums.values(Card.Rank)) |rank| {
                    deck_tmp[i] = .{ .suit = suit, .rank = rank };
                    i += 1;
                }
            }

            break :blk deck_tmp;
        };

        // TODO: research alternatives for seeding and randomising
        var prng = std.rand.DefaultPrng.init(seed);
        var random = prng.random();
        random.shuffle(Card, &deck);

        const CascadeArrayType = std.BoundedArray(Card, CASCADE_CARD_LIMIT);
        return .{
            .open_slots = .{ null, null, null, null },
            .foundations = std.EnumArray(Card.Suit, ?Card.Rank).initFill(null),
            .cascades = .{
                CascadeArrayType.fromSlice(deck[0..7]) catch unreachable,
                CascadeArrayType.fromSlice(deck[7..14]) catch unreachable,
                CascadeArrayType.fromSlice(deck[14..21]) catch unreachable,
                CascadeArrayType.fromSlice(deck[21..28]) catch unreachable,
                CascadeArrayType.fromSlice(deck[28..34]) catch unreachable,
                CascadeArrayType.fromSlice(deck[34..40]) catch unreachable,
                CascadeArrayType.fromSlice(deck[40..46]) catch unreachable,
                CascadeArrayType.fromSlice(deck[46..52]) catch unreachable,
            },
        };
    }
};

const App = struct {
    canvas: Canvas,
    freecell: Freecell,
    mouse_pressed_prev_frame: bool,
    fullscreen: bool, // must keep in synced with js world
    win: bool, // set when game is finished
    fps_accum: f32,
    fps_cache: f32,
    frame_cnt: usize,
    highlight_moves: bool,
    current_game_seed: u32,
    drag: ?DragState,
    animation: ?AnimationState,

    const Canvas = d2.CachedCanvas;

    const DragState = struct {
        offset_x: i32,
        offset_y: i32,
        top_card_pos: Freecell.CardPos, // position of card that was moved
    };

    const AnimationState = struct {
        from: Freecell.CardPos,
        begin_time: f32,
    };

    pub fn init(main_image: d2.Image) App {
        const seed = wasm.seed();
        return .{
            .canvas = Canvas.init(main_image),
            .freecell = Freecell.init(seed),
            .current_game_seed = seed,
            .mouse_pressed_prev_frame = false,
            .drag = null,
            .win = false,
            .fps_accum = 0,
            .fps_cache = 0,
            .frame_cnt = 0,
            .highlight_moves = true,
            .fullscreen = false,
            .animation = null,
        };
    }

    pub fn fullscreen_mode(g: *App, mode: bool) void {
        g.fullscreen = mode;
    }

    pub fn resize(g: *App, new_image: d2.Image) void {
        g.canvas.resize(new_image);
    }

    fn newGame(g: *App) void {
        g.resetUI();
        const seed = wasm.seed();
        g.freecell = Freecell.init(seed);
        g.win = false;
        g.current_game_seed = seed;
    }

    fn restartGame(g: *App) void {
        g.resetUI();
        g.win = false;
        g.freecell = Freecell.init(g.current_game_seed);
    }

    fn resetUI(g: *App) void {
        g.mouse_pressed_prev_frame = false;
        g.drag = null;
        g.animation = null;
    }

    const animation_time = 300; // ms

    const ui_height = 50;
    const ui_fullscreen_w = 50;
    const ui_new_game_w = 125;
    const ui_restart_game_w = 165;
    const ui_highlight_w = 250;
    const ui_shift = 25;

    const card_w = 88;
    const card_h = 124;
    const card_x_gap = 20;
    const card_y_shift = 30;

    const main_board_y_shift = 180;
    const main_board_width = 8 * card_w + (8 - 1) * card_x_gap;

    const top_line_y = 20;

    fn cardDropPos(g: *App, card_region: RectRegion) ?Freecell.CardPos { // card position, ignore cascade row
        const width = g.canvas.width();
        const height = g.canvas.height();
        const main_board_x_shift = @divTrunc(width - main_board_width, 2);
        const top_line_x = main_board_x_shift;

        var best_area: i64 = 0; // search of best intersection
        var best_pos: ?Freecell.CardPos = null;
        for (0..4) |i| { // open slots
            const x = @as(i32, @intCast(i)) * (card_w + card_x_gap) + top_line_x;
            const y = top_line_y;
            const intersect_area = card_region.intersect(.{ .x = x, .y = y, .w = card_w, .h = card_h }).area();
            if (intersect_area > best_area) {
                best_area = intersect_area;
                best_pos = .{ .open_slot = @intCast(i) };
            }
        }
        for (0..8) |i| { // cascades
            const x = @as(i32, @intCast(i)) * (card_w + card_x_gap) + main_board_x_shift;
            const y = main_board_y_shift;
            const intersect_area = card_region.intersect(.{ .x = x, .y = y, .w = card_w, .h = height - main_board_y_shift }).area();
            if (intersect_area > best_area) {
                best_area = intersect_area;
                best_pos = .{ .cascade = .{ @intCast(i), 0 } };
            }
        }
        for (0..4) |i| { // foundation
            const x = @as(i32, @intCast(i + 4)) * (card_w + card_x_gap) + top_line_x;
            const y = top_line_y;
            const intersect_area = card_region.intersect(.{ .x = x, .y = y, .w = card_w, .h = card_h }).area();
            if (intersect_area > best_area) {
                best_area = intersect_area;
                best_pos = .{ .foundation = @intCast(i) };
            }
        }
        return best_pos;
    }

    fn cardRegionFromPos(g: *App, pos: Freecell.CardPos) RectRegion {
        const width = g.canvas.width();
        const main_board_x_shift = @divTrunc(width - main_board_width, 2);
        const top_line_x = main_board_x_shift;
        switch (pos) {
            .cascade => |ij| {
                const i = ij[0];
                const j = ij[1];
                const x = @as(i32, @intCast(i)) * (card_w + card_x_gap) + main_board_x_shift;
                const y = @as(i32, @intCast(j)) * card_y_shift + main_board_y_shift;
                return .{ .x = x, .y = y, .w = card_w, .h = card_h };
            },
            .open_slot => |i| {
                const x = @as(i32, @intCast(i)) * (card_w + card_x_gap) + top_line_x;
                const y = top_line_y;
                return .{ .x = x, .y = y, .w = card_w, .h = card_h };
            },
            .foundation => |i| {
                const x = @as(i32, @intCast(i + 4)) * (card_w + card_x_gap) + top_line_x;
                const y = top_line_y;
                return .{ .x = x, .y = y, .w = card_w, .h = card_h };
            },
        }
    }

    fn cardClickPos(g: *App, click_x: i32, click_y: i32) ?Freecell.CardPos { // card position
        const width = g.canvas.width();
        const height = g.canvas.height();
        _ = height;
        const main_board_x_shift = @divTrunc(width - main_board_width, 2);
        const top_line_x = main_board_x_shift;

        for (0..4) |i| { // open slots
            const x = @as(i32, @intCast(i)) * (card_w + card_x_gap) + top_line_x;
            const y = top_line_y;
            const region: RectRegion = .{ .x = x, .y = y, .w = card_w, .h = card_h };
            if (region.inside(click_x, click_y)) {
                return .{ .open_slot = @intCast(i) };
            }
        }
        for (g.freecell.cascades, 0..) |cascade, i| { // cascades
            for (cascade.slice(), 0..) |_, j| {
                const x = @as(i32, @intCast(i)) * (card_w + card_x_gap) + main_board_x_shift;
                const y = @as(i32, @intCast(j)) * card_y_shift + main_board_y_shift;
                const region: RectRegion = blk: {
                    if (j != cascade.len - 1) break :blk .{ .x = x, .y = y, .w = card_w, .h = card_y_shift };
                    break :blk .{ .x = x, .y = y, .w = card_w, .h = card_h }; // last card
                };
                if (region.inside(click_x, click_y)) {
                    return .{ .cascade = .{ @intCast(i), @intCast(j) } };
                }
            }
        }
        return null;
    }

    pub fn frame(g: *App, mouse_x: i32, mouse_y: i32, mouse_inside: bool, mouse_pressed: bool, time: f32, fps: f32) void {
        {
            g.fps_accum = 0.80 * g.fps_accum + 0.20 * fps;
            g.frame_cnt += 1;
            if (g.frame_cnt == 5) {
                g.frame_cnt = 0;
                g.fps_cache = g.fps_accum;
            }
        }

        const width = g.canvas.width();
        const height = g.canvas.height();
        const main_board_x_shift = @divTrunc(width - main_board_width, 2);
        const top_line_x = main_board_x_shift;

        const clicked = mouse_pressed and !g.mouse_pressed_prev_frame;
        g.mouse_pressed_prev_frame = mouse_pressed;

        if (!g.win and g.freecell.isWin()) {
            g.win = true;
            wasm._win_sound();
        }

        if (g.animation) |anim| {
            if (time - anim.begin_time >= animation_time) {
                const card = g.freecell.cardsFromPos(anim.from).get(0);
                _ = g.freecell.attemptMove(anim.from, .{ .foundation = @intFromEnum(card.suit) });
                if (g.freecell.findFoundationAutomove()) |from_pos| {
                    wasm._card_sound();
                    g.animation = .{
                        .from = from_pos,
                        .begin_time = time,
                    };
                } else {
                    g.animation = null;
                }
            }
        }
        if (g.animation == null) {
            if (clicked) {
                if (g.cardClickPos(mouse_x, mouse_y)) |pos| {
                    if (g.freecell.isMovable(pos)) {
                        const card_region = g.cardRegionFromPos(pos);
                        g.drag = .{
                            .offset_x = mouse_x - card_region.x,
                            .offset_y = mouse_y - card_region.y,
                            .top_card_pos = pos,
                        };
                    }
                }
                { // ui
                    var new_game_region: RectRegion = .{ .x = ui_shift, .y = height - ui_shift - ui_height, .w = ui_new_game_w, .h = ui_height };
                    var restart_game_region: RectRegion = .{ .x = 2 * ui_shift + ui_new_game_w, .y = height - ui_shift - ui_height, .w = ui_restart_game_w, .h = ui_height };
                    var highlight_region: RectRegion = .{ .x = 3 * ui_shift + ui_new_game_w + ui_restart_game_w, .y = height - ui_shift - ui_height, .w = ui_highlight_w, .h = ui_height };
                    var fullscreen_region: RectRegion = .{ .x = width - ui_shift - ui_fullscreen_w, .y = height - ui_shift - ui_height, .w = ui_fullscreen_w, .h = ui_height };
                    if (new_game_region.inside(mouse_x, mouse_y)) {
                        g.newGame();
                    }
                    if (restart_game_region.inside(mouse_x, mouse_y)) {
                        g.restartGame();
                    }
                    if (highlight_region.inside(mouse_x, mouse_y)) {
                        g.highlight_moves = !g.highlight_moves;
                    }
                    if (fullscreen_region.inside(mouse_x, mouse_y)) {
                        wasm.fullscreen(!g.fullscreen);
                        g.fullscreen = !g.fullscreen;
                    }
                }
            }

            if (!mouse_pressed) {
                if (g.drag) |d| blk: {
                    const card_region: RectRegion = .{ .x = mouse_x - d.offset_x, .y = mouse_y - d.offset_y, .w = card_w, .h = card_h };
                    const to = g.cardDropPos(card_region) orelse break :blk;
                    if (g.freecell.attemptMove(d.top_card_pos, to)) {
                        if (g.freecell.findFoundationAutomove()) |from_pos| {
                            wasm._card_sound();
                            g.animation = .{
                                .from = from_pos,
                                .begin_time = time,
                            };
                        }
                    }
                }
                g.drag = null;
            }
        }

        // draw

        const BOARD_COLOR: d2.RGBA = .{ .r = 0x00, .g = 0x80, .b = 0x00, .a = 0xFF };
        const MAIN_BOARD_COLOR: d2.RGBA = .{ .r = 0x00, .g = 0x70, .b = 0x00, .a = 0xFF };
        const HIGHLIGHT_COLOR: d2.RGBA = .{ .r = 0x00, .g = 0x50, .b = 0x00, .a = 0xFF };
        const LIGHT_HIGHLIGHT_COLOR: d2.RGBA = .{ .r = 0x00, .g = 0xD7, .b = 0x00, .a = 0xFF };
        const GOLD_COLOR: d2.RGBA = .{ .r = 0xFF, .g = 0xD7, .b = 0x00, .a = 0xFF };

        g.canvas.drawColor(BOARD_COLOR);

        {
            const border1 = 14;
            const border2 = border1 + 2;
            const y_off = 50;
            const x = main_board_x_shift;
            const y = main_board_y_shift;
            g.canvas.drawRect(x - border2, y - border2, main_board_width + 2 * border2, height - y - 2 * border1 - y_off, d2.RGBA.BLACK);
            g.canvas.drawRect(x - border1, y - border1, main_board_width + 2 * border1, height - y - 2 * border2 - y_off, MAIN_BOARD_COLOR);
        }

        for (g.freecell.cascades, 0..) |cascade, i| {
            var draw_cards: usize = 0;
            for (cascade.slice(), 0..) |card, j| {
                if (g.drag) |d| if (d.top_card_pos == .cascade and d.top_card_pos.cascade[0] == i and d.top_card_pos.cascade[1] == j) break;
                if (g.animation) |anim| if (anim.from == .cascade and anim.from.cascade[0] == i and anim.from.cascade[1] == j) break;
                const x = @as(i32, @intCast(i)) * (card_w + card_x_gap) + main_board_x_shift;
                const y = @as(i32, @intCast(j)) * card_y_shift + main_board_y_shift;
                if (g.highlight_moves) {
                    const pos: Freecell.CardPos = .{ .cascade = .{ @intCast(i), @intCast(j) } };
                    if (g.freecell.isMovable(pos)) {
                        g.canvas.drawSprite(x, y, cardToSprite(card), null);
                    } else {
                        g.canvas.drawSprite(x, y, cardToSprite(card), 2.0);
                    }
                } else {
                    g.canvas.drawSprite(x, y, cardToSprite(card), null);
                }
                draw_cards += 1;
            }
            if (draw_cards == 0) {
                const x = @as(i32, @intCast(i)) * (card_w + card_x_gap) + main_board_x_shift;
                const y = main_board_y_shift;
                g.canvas.drawRect(x, y, card_w, card_h, HIGHLIGHT_COLOR);
            }
        }

        for (0..4) |i| {
            const x = @as(i32, @intCast(i)) * (card_w + card_x_gap) + top_line_x;
            const y = top_line_y;
            const light_border = 1;
            g.canvas.drawRect(x - light_border, y - light_border, card_w + 2 * light_border, card_h + 2 * light_border, LIGHT_HIGHLIGHT_COLOR);
            g.canvas.drawRect(x, y, card_w, card_h, HIGHLIGHT_COLOR);
        }

        for (0..4) |i| {
            if (g.drag) |d| if (d.top_card_pos == .open_slot and d.top_card_pos.open_slot == i) continue;
            if (g.animation) |anim| if (anim.from == .open_slot and anim.from.open_slot == i) continue;
            if (g.freecell.open_slots[i]) |card| {
                const x = @as(i32, @intCast(i)) * (card_w + card_x_gap) + top_line_x;
                const y = top_line_y;
                g.canvas.drawSprite(x, y, cardToSprite(card), null);
            }
        }

        for (4..8) |i| {
            const x = @as(i32, @intCast(i)) * (card_w + card_x_gap) + top_line_x;
            const y = top_line_y;
            const gold_border = 1;
            g.canvas.drawRect(x - gold_border, y - gold_border, card_w + 2 * gold_border, card_h + 2 * gold_border, GOLD_COLOR);
            g.canvas.drawRect(x, y, card_w, card_h, HIGHLIGHT_COLOR);
        }

        for (std.enums.values(Card.Suit), 0..) |suit, i| {
            const x = @as(i32, @intCast(i + 4)) * (card_w + card_x_gap) + top_line_x;
            const y = top_line_y;

            if (g.freecell.foundations.get(suit)) |rank| {
                g.canvas.drawSprite(x, y, cardToSprite(.{ .suit = suit, .rank = rank }), null);
            } else {
                g.canvas.drawSprite(x, y, suitToSprite(suit), null);
            }
        }

        if (g.drag) |d| {
            var cards = g.freecell.cardsFromPos(d.top_card_pos);

            const card_off_x = mouse_x - d.offset_x;
            const card_off_y = mouse_y - d.offset_y;

            for (cards.slice(), 0..) |card, j| {
                const x = card_off_x;
                const y = @as(i32, @intCast(j)) * card_y_shift + card_off_y;
                g.canvas.drawSprite(x, y, cardToSprite(card), null);
            }
        }

        if (g.animation) |anim| {
            const card = g.freecell.cardsFromPos(anim.from).get(0);
            const from_region: RectRegion = switch (anim.from) {
                .cascade => |ij| blk: {
                    const x = @as(i32, @intCast(ij[0])) * (card_w + card_x_gap) + main_board_x_shift;
                    const y = @as(i32, @intCast(ij[1])) * card_y_shift + main_board_y_shift;
                    break :blk .{ .x = x, .y = y, .w = card_w, .h = card_h };
                },
                .open_slot => |i| blk: {
                    const x = @as(i32, @intCast(i)) * (card_w + card_x_gap) + top_line_x;
                    const y = top_line_y;
                    break :blk .{ .x = x, .y = y, .w = card_w, .h = card_h };
                },
                .foundation => unreachable,
            };
            const to_region: RectRegion = blk: {
                const i: i32 = @intFromEnum(card.suit);
                const x = (i + 4) * (card_w + card_x_gap) + top_line_x;
                const y = top_line_y;
                break :blk .{ .x = x, .y = y, .w = card_w, .h = card_h };
            };

            const t = (time - anim.begin_time) / animation_time;
            const x: i32 = @intFromFloat(@floor(std.math.lerp(@as(f32, @floatFromInt(from_region.x)), @as(f32, @floatFromInt(to_region.x)), t)));
            const y: i32 = @intFromFloat(@floor(std.math.lerp(@as(f32, @floatFromInt(from_region.y)), @as(f32, @floatFromInt(to_region.y)), t)));
            g.canvas.drawSprite(x, y, cardToSprite(card), null);
        }

        { // ui draw
            var new_game_region: RectRegion = .{ .x = ui_shift, .y = height - ui_shift - ui_height, .w = ui_new_game_w, .h = ui_height };
            var restart_game_region: RectRegion = .{ .x = 2 * ui_shift + ui_new_game_w, .y = height - ui_shift - ui_height, .w = ui_restart_game_w, .h = ui_height };
            var highlight_region: RectRegion = .{ .x = 3 * ui_shift + ui_new_game_w + ui_restart_game_w, .y = height - ui_shift - ui_height, .w = ui_highlight_w, .h = ui_height };
            var fullscreen_region: RectRegion = .{ .x = width - ui_shift - ui_fullscreen_w, .y = height - ui_shift - ui_height, .w = ui_fullscreen_w, .h = ui_height };
            if (new_game_region.inside(mouse_x, mouse_y)) {
                g.canvas.drawSprite(new_game_region.x, new_game_region.y, d2.Sprites.new_game_hover, null);
            } else {
                g.canvas.drawSprite(new_game_region.x, new_game_region.y, d2.Sprites.new_game, null);
            }
            if (restart_game_region.inside(mouse_x, mouse_y)) {
                g.canvas.drawSprite(restart_game_region.x, restart_game_region.y, d2.Sprites.restart_game_hover, null);
            } else {
                g.canvas.drawSprite(restart_game_region.x, restart_game_region.y, d2.Sprites.restart_game, null);
            }
            if (highlight_region.inside(mouse_x, mouse_y)) {
                if (!g.highlight_moves) {
                    g.canvas.drawSprite(highlight_region.x, highlight_region.y, d2.Sprites.highlight_on_hover, null);
                } else {
                    g.canvas.drawSprite(highlight_region.x, highlight_region.y, d2.Sprites.highlight_off_hover, null);
                }
            } else {
                if (!g.highlight_moves) {
                    g.canvas.drawSprite(highlight_region.x, highlight_region.y, d2.Sprites.highlight_on, null);
                } else {
                    g.canvas.drawSprite(highlight_region.x, highlight_region.y, d2.Sprites.highlight_off, null);
                }
            }
            if (fullscreen_region.inside(mouse_x, mouse_y)) {
                if (!g.fullscreen) {
                    g.canvas.drawSprite(fullscreen_region.x, fullscreen_region.y, d2.Sprites.fullscreen_on_hover, null);
                } else {
                    g.canvas.drawSprite(fullscreen_region.x, fullscreen_region.y, d2.Sprites.fullscreen_off_hover, null);
                }
            } else {
                if (!g.fullscreen) {
                    g.canvas.drawSprite(fullscreen_region.x, fullscreen_region.y, d2.Sprites.fullscreen_on, null);
                } else {
                    g.canvas.drawSprite(fullscreen_region.x, fullscreen_region.y, d2.Sprites.fullscreen_off, null);
                }
            }

            { // TODO: add toggle + harder: fps show value of time taken for frame not vsynced one
                const border1 = 5;
                const border2 = border1 + 2;
                const x = 20;
                const y = 20;
                const w = 145;
                const h = 14;
                g.canvas.drawRect(x - border2, y - border2, w + 2 * border2, h + 2 * border2, d2.RGBA.BLACK);
                g.canvas.drawRect(x - border1, y - border1, w + 2 * border1, h + 2 * border1, d2.RGBA.WHITE);

                const shift = 10 + 2;
                {
                    var i: i32 = 0;
                    g.canvas.drawSprite(x + shift * i, y, d2.Sprites.fpsfont_F, null);
                    i += 1;
                    g.canvas.drawSprite(x + shift * i, y, d2.Sprites.fpsfont_P, null);
                    i += 1;
                    g.canvas.drawSprite(x + shift * i, y, d2.Sprites.fpsfont_S, null);
                    i += 1;
                    g.canvas.drawSprite(x + shift * i, y, d2.Sprites.@"fpsfont_:", null);
                    i += 1;
                    i += 1;
                    var buf: [128]u8 = undefined;
                    const out = std.fmt.bufPrint(&buf, "{d:.2}", .{g.fps_cache}) catch unreachable;
                    i += @intCast(7 - out.len);
                    for (out) |sym| {
                        const sprite: d2.Sprites = switch (sym) {
                            '0' => .fpsfont_0,
                            '1' => .fpsfont_1,
                            '2' => .fpsfont_2,
                            '3' => .fpsfont_3,
                            '4' => .fpsfont_4,
                            '5' => .fpsfont_5,
                            '6' => .fpsfont_6,
                            '7' => .fpsfont_7,
                            '8' => .fpsfont_8,
                            '9' => .fpsfont_9,
                            '.' => .@"fpsfont_.",
                            else => unreachable,
                        };
                        g.canvas.drawSprite(x + shift * i, y, sprite, null);
                        i += 1;
                    }
                }
            }
        }

        if (g.win) {
            const text_w = 32;
            const gap = 4;
            // const text_h = 32;
            const letters = [_]?d2.Sprites{ .text_y, .text_o, .text_u, null, .text_w, .text_i, .text_n };
            const text_all_w = @as(i32, @intCast(letters.len)) * (text_w + gap) - gap;
            const text_shift_x = @divTrunc(width - text_all_w, 2);
            for (letters, 0..) |sprite, i| {
                if (sprite == null) continue;
                const x = @as(i32, @intCast(i)) * (text_w + gap) + text_shift_x;
                const delta = time / 300 + @as(f32, @floatFromInt(i)) / 2;
                const A = 10;
                const y: i32 = @as(i32, @intFromFloat(@trunc(std.math.sin(delta) * A))) + main_board_y_shift + 200;
                g.canvas.drawSprite(x, y, sprite.?, null);
            }
        }

        if (mouse_inside) {
            g.canvas.drawSprite(mouse_x, mouse_y, d2.Sprites.cursor, null);
        }

        g.canvas.finalize();
    }
};
