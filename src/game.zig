const std = @import("std");
const pf = @import("platform.zig");
const d2 = @import("d2.zig");
const Rect = @import("Rect.zig");
const Sprite = @import("Sprite");

const Game = @This();

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
            return (s1.isRed() and s2.isBlack()) or (s1.isBlack() and s2.isRed());
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
            return @as(i32, @intFromEnum(r1)) - @as(i32, @intFromEnum(r2));
        }
    };

    suit: Suit,
    rank: Rank,
};

fn sprite_from_card(card: Card) *const Sprite {
    switch (card.suit) {
        inline else => |suit| {
            switch (card.rank) {
                inline else => |rank| {
                    const suit_str = @tagName(suit);
                    const rank_str = @tagName(rank);
                    return &@field(Sprite, suit_str ++ "_" ++ rank_str);
                },
            }
        },
    }
}

fn sprite_from_foundation_suit(suit: Card.Suit) *const Sprite {
    switch (suit) {
        inline else => |s| {
            const suit_str = @tagName(s);
            return &@field(Sprite, suit_str ++ "_foundation");
        },
    }
}

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

canvas: d2.Canvas,
freecell: Freecell,
mouse_pressed_prev_frame: bool,
win: bool, // set when game is finished
fps_accum: f32,
fps_cache: f32,
frame_cnt: usize,
highlight_moves: bool,
current_game_seed: u32,
drag: ?DragState,
animation: ?AnimationState,

const DragState = struct {
    offset_x: i32,
    offset_y: i32,
    top_card_pos: Freecell.CardPos, // position of card that was moved
};

const AnimationState = struct {
    from: Freecell.CardPos,
    begin_time: f64,
};

pub fn init(gpa: std.mem.Allocator, w: i32, h: i32) Game {
    const seed = pf.get_random_u32();
    const surf: d2.Surface = .{
        .pixels = gpa.alloc(d2.RGBA, @intCast(w * h)) catch unreachable,
        .w = w,
        .h = h,
    };
    return .{
        .canvas = d2.Canvas.init(surf),
        .freecell = Freecell.init(seed),
        .current_game_seed = seed,
        .mouse_pressed_prev_frame = false,
        .drag = null,
        .win = false,
        .fps_accum = 0,
        .fps_cache = 0,
        .frame_cnt = 0,
        .highlight_moves = true,
        .animation = null,
    };
}

fn start_new_game(g: *Game) void {
    g.reset_ui();
    const seed = pf.get_random_u32();
    g.freecell = Freecell.init(seed);
    g.win = false;
    g.current_game_seed = seed;
}

fn restart_game(g: *Game) void {
    g.reset_ui();
    g.win = false;
    g.freecell = Freecell.init(g.current_game_seed);
}

fn reset_ui(g: *Game) void {
    g.mouse_pressed_prev_frame = false;
    g.drag = null;
    g.animation = null;
}

const animation_time = 300; // ms

const ui_height = 50;
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

fn cardDropPos(g: *Game, card_region: Rect) ?Freecell.CardPos { // card position, ignore cascade row
    const width = g.canvas.surf.w;
    const height = g.canvas.surf.h;
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

fn cardRegionFromPos(g: *Game, pos: Freecell.CardPos) Rect {
    const width = g.canvas.surf.w;
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

fn cardClickPos(g: *Game, click_x: i32, click_y: i32) ?Freecell.CardPos { // card position
    const width = g.canvas.surf.w;
    const height = g.canvas.surf.h;
    _ = height;
    const main_board_x_shift = @divTrunc(width - main_board_width, 2);
    const top_line_x = main_board_x_shift;

    for (0..4) |i| { // open slots
        const x = @as(i32, @intCast(i)) * (card_w + card_x_gap) + top_line_x;
        const y = top_line_y;
        const region: Rect = .{ .x = x, .y = y, .w = card_w, .h = card_h };
        if (region.inside(click_x, click_y)) {
            if (g.freecell.open_slots[@intCast(i)] == null) return null;
            return .{ .open_slot = @intCast(i) };
        }
    }
    for (g.freecell.cascades, 0..) |cascade, i| { // cascades
        for (cascade.slice(), 0..) |_, j| {
            const x = @as(i32, @intCast(i)) * (card_w + card_x_gap) + main_board_x_shift;
            const y = @as(i32, @intCast(j)) * card_y_shift + main_board_y_shift;
            const region: Rect = blk: {
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

pub fn frame(g: *Game) void {
    g.canvas.begin_frame();

    const mouse_x = pf.get_mouse_x();
    const mouse_y = pf.get_mouse_y();
    const mouse_inside = pf.is_mouse_inside();
    const main_button_down = pf.is_mouse_button_down(.main);
    const time = pf.get_timestamp();

    {
        g.fps_accum = 0.80 * g.fps_accum + 0.20 * 60;
        g.frame_cnt += 1;
        if (g.frame_cnt == 5) {
            g.frame_cnt = 0;
            g.fps_cache = g.fps_accum;
        }
    }

    const width = g.canvas.surf.w;
    const height = g.canvas.surf.h;
    const main_board_x_shift = @divTrunc(width - main_board_width, 2);
    const top_line_x = main_board_x_shift;

    const clicked = main_button_down and !g.mouse_pressed_prev_frame;
    g.mouse_pressed_prev_frame = main_button_down;

    if (!g.win and g.freecell.isWin()) {
        g.win = true;
        pf.play_sound("win");
    }

    if (g.animation) |anim| {
        if (time - anim.begin_time >= animation_time) {
            const card = g.freecell.cardsFromPos(anim.from).get(0);
            _ = g.freecell.attemptMove(anim.from, .{ .foundation = @intFromEnum(card.suit) });
            if (g.freecell.findFoundationAutomove()) |from_pos| {
                pf.play_sound("card");
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
                var new_game_region: Rect = .{ .x = ui_shift, .y = height - ui_shift - ui_height, .w = ui_new_game_w, .h = ui_height };
                var restart_game_region: Rect = .{ .x = 2 * ui_shift + ui_new_game_w, .y = height - ui_shift - ui_height, .w = ui_restart_game_w, .h = ui_height };
                var highlight_region: Rect = .{ .x = 3 * ui_shift + ui_new_game_w + ui_restart_game_w, .y = height - ui_shift - ui_height, .w = ui_highlight_w, .h = ui_height };
                if (new_game_region.inside(mouse_x, mouse_y)) {
                    g.start_new_game();
                }
                if (restart_game_region.inside(mouse_x, mouse_y)) {
                    g.restart_game();
                }
                if (highlight_region.inside(mouse_x, mouse_y)) {
                    g.highlight_moves = !g.highlight_moves;
                }
            }
        }

        if (!main_button_down) {
            if (g.drag) |d| make_move: {
                const card_region: Rect = .{ .x = mouse_x - d.offset_x, .y = mouse_y - d.offset_y, .w = card_w, .h = card_h };
                const to = g.cardDropPos(card_region) orelse break :make_move;
                if (g.freecell.attemptMove(d.top_card_pos, to)) {
                    if (g.freecell.findFoundationAutomove()) |from_pos| {
                        pf.play_sound("card");
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

    const BOARD_COLOR: d2.RGBA = .{ .r = 0x00, .g = 0x80, .b = 0x00, .a = 0xFF };
    const MAIN_BOARD_COLOR: d2.RGBA = .{ .r = 0x00, .g = 0x70, .b = 0x00, .a = 0xFF };
    const HIGHLIGHT_COLOR: d2.RGBA = .{ .r = 0x00, .g = 0x50, .b = 0x00, .a = 0xFF };
    const LIGHT_HIGHLIGHT_COLOR: d2.RGBA = .{ .r = 0x00, .g = 0xD7, .b = 0x00, .a = 0xFF };
    const GOLD_COLOR: d2.RGBA = .{ .r = 0xFF, .g = 0xD7, .b = 0x00, .a = 0xFF };
    const BLACK: d2.RGBA = .{ .r = 0x00, .g = 0x00, .b = 0x00, .a = 0xFF };
    const WHITE: d2.RGBA = .{ .r = 0xFF, .g = 0xFF, .b = 0xFF, .a = 0xFF };

    const main_board_rect: Rect = .{ .x = main_board_x_shift, .y = main_board_y_shift, .w = main_board_width, .h = height - main_board_y_shift - 120 };

    g.canvas.draw_rect(Rect.from_wh(width, height), BOARD_COLOR);

    g.canvas.draw_rect(main_board_rect.inset(-16, -16), BLACK);
    g.canvas.draw_rect(main_board_rect.inset(-14, -14), MAIN_BOARD_COLOR);

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
                    g.canvas.draw_sprite(sprite_from_card(card), x, y);
                } else {
                    g.canvas.draw_sprite(sprite_from_card(card), x, y);
                }
            } else {
                g.canvas.draw_sprite(sprite_from_card(card), x, y);
            }
            draw_cards += 1;
        }
        if (draw_cards == 0) {
            const x = @as(i32, @intCast(i)) * (card_w + card_x_gap) + main_board_x_shift;
            const y = main_board_y_shift;
            g.canvas.draw_rect(Rect.from_wh(card_w, card_h).offset(x, y), HIGHLIGHT_COLOR);
        }
    }

    for (0..4) |i| {
        const x = @as(i32, @intCast(i)) * (card_w + card_x_gap) + top_line_x;
        const y = top_line_y;
        g.canvas.draw_rect(Rect.from_wh(card_w, card_h).offset(x, y).inset(-1, -1), LIGHT_HIGHLIGHT_COLOR);
        g.canvas.draw_rect(Rect.from_wh(card_w, card_h).offset(x, y), HIGHLIGHT_COLOR);
    }

    for (0..4) |i| {
        if (g.drag) |d| if (d.top_card_pos == .open_slot and d.top_card_pos.open_slot == i) continue;
        if (g.animation) |anim| if (anim.from == .open_slot and anim.from.open_slot == i) continue;
        if (g.freecell.open_slots[i]) |card| {
            const x = @as(i32, @intCast(i)) * (card_w + card_x_gap) + top_line_x;
            const y = top_line_y;
            g.canvas.draw_sprite(sprite_from_card(card), x, y);
        }
    }

    for (4..8) |i| {
        const x = @as(i32, @intCast(i)) * (card_w + card_x_gap) + top_line_x;
        const y = top_line_y;
        g.canvas.draw_rect(Rect.from_wh(card_w, card_h).offset(x, y).inset(-1, -1), GOLD_COLOR);
        g.canvas.draw_rect(Rect.from_wh(card_w, card_h).offset(x, y), HIGHLIGHT_COLOR);
    }

    for (std.enums.values(Card.Suit), 0..) |suit, i| {
        const x = @as(i32, @intCast(i + 4)) * (card_w + card_x_gap) + top_line_x;
        const y = top_line_y;

        if (g.freecell.foundations.get(suit)) |rank| {
            const card: Card = .{ .suit = suit, .rank = rank };
            g.canvas.draw_sprite(sprite_from_card(card), x, y);
        } else {
            g.canvas.draw_sprite(sprite_from_foundation_suit(suit), x, y);
        }
    }

    if (g.drag) |d| {
        var cards = g.freecell.cardsFromPos(d.top_card_pos);

        const card_off_x = mouse_x - d.offset_x;
        const card_off_y = mouse_y - d.offset_y;

        for (cards.slice(), 0..) |card, j| {
            const x = card_off_x;
            const y = @as(i32, @intCast(j)) * card_y_shift + card_off_y;
            g.canvas.draw_sprite(sprite_from_card(card), x, y);
        }
    }

    if (g.animation) |anim| {
        const card = g.freecell.cardsFromPos(anim.from).get(0);
        const from_region: Rect = switch (anim.from) {
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
        const to_region: Rect = rect: {
            const i: i32 = @intFromEnum(card.suit);
            const x = (i + 4) * (card_w + card_x_gap) + top_line_x;
            const y = top_line_y;
            break :rect .{ .x = x, .y = y, .w = card_w, .h = card_h };
        };

        const t = (time - anim.begin_time) / animation_time;
        const x: i32 = @intFromFloat(@floor(std.math.lerp(@as(f32, @floatFromInt(from_region.x)), @as(f32, @floatFromInt(to_region.x)), t)));
        const y: i32 = @intFromFloat(@floor(std.math.lerp(@as(f32, @floatFromInt(from_region.y)), @as(f32, @floatFromInt(to_region.y)), t)));
        g.canvas.draw_sprite(sprite_from_card(card), x, y);
    }

    { // ui draw
        var new_game_region: Rect = .{ .x = ui_shift, .y = height - ui_shift - ui_height, .w = ui_new_game_w, .h = ui_height };
        var restart_game_region: Rect = .{ .x = 2 * ui_shift + ui_new_game_w, .y = height - ui_shift - ui_height, .w = ui_restart_game_w, .h = ui_height };
        var highlight_region: Rect = .{ .x = 3 * ui_shift + ui_new_game_w + ui_restart_game_w, .y = height - ui_shift - ui_height, .w = ui_highlight_w, .h = ui_height };
        if (new_game_region.inside(mouse_x, mouse_y)) {
            g.canvas.draw_sprite(&Sprite.new_game_hover, new_game_region.x, new_game_region.y);
        } else {
            g.canvas.draw_sprite(&Sprite.new_game, new_game_region.x, new_game_region.y);
        }
        if (restart_game_region.inside(mouse_x, mouse_y)) {
            g.canvas.draw_sprite(&Sprite.restart_game_hover, restart_game_region.x, restart_game_region.y);
        } else {
            g.canvas.draw_sprite(&Sprite.restart_game, restart_game_region.x, restart_game_region.y);
        }
        if (highlight_region.inside(mouse_x, mouse_y)) {
            if (!g.highlight_moves) {
                g.canvas.draw_sprite(&Sprite.highlight_on_hover, highlight_region.x, highlight_region.y);
            } else {
                g.canvas.draw_sprite(&Sprite.highlight_off_hover, highlight_region.x, highlight_region.y);
            }
        } else {
            if (!g.highlight_moves) {
                g.canvas.draw_sprite(&Sprite.highlight_on, highlight_region.x, highlight_region.y);
            } else {
                g.canvas.draw_sprite(&Sprite.highlight_off, highlight_region.x, highlight_region.y);
            }
        }

        { // TODO: add toggle + harder: fps show value of time taken for frame not vsynced one
            const x = 20;
            const y = 20;
            const w = 145;
            const h = 14;
            const rect: Rect = .{ .x = x, .y = y, .w = w, .h = h };
            g.canvas.draw_rect(rect.inset(-5, -5), BLACK);
            g.canvas.draw_rect(rect.inset(-7, -7), WHITE);

            const shift = 10 + 2;
            {
                var i: i32 = 0;
                g.canvas.draw_sprite(&Sprite.fpsfont_F, x + shift * i, y);
                i += 1;
                g.canvas.draw_sprite(&Sprite.fpsfont_P, x + shift * i, y);
                i += 1;
                g.canvas.draw_sprite(&Sprite.fpsfont_S, x + shift * i, y);
                i += 1;
                g.canvas.draw_sprite(&Sprite.@"fpsfont_:", x + shift * i, y);
                i += 1;
                i += 1;
                var buf: [128]u8 = undefined;
                const out = std.fmt.bufPrint(&buf, "{d:.2}", .{g.fps_cache}) catch unreachable;
                i += @intCast(7 - out.len);
                for (out) |sym| {
                    const sprite = switch (sym) {
                        '0' => &Sprite.fpsfont_0,
                        '1' => &Sprite.fpsfont_1,
                        '2' => &Sprite.fpsfont_2,
                        '3' => &Sprite.fpsfont_3,
                        '4' => &Sprite.fpsfont_4,
                        '5' => &Sprite.fpsfont_5,
                        '6' => &Sprite.fpsfont_6,
                        '7' => &Sprite.fpsfont_7,
                        '8' => &Sprite.fpsfont_8,
                        '9' => &Sprite.fpsfont_9,
                        '.' => &Sprite.@"fpsfont_.",
                        else => unreachable,
                    };
                    g.canvas.draw_sprite(sprite, x + shift * i, y);
                    i += 1;
                }
            }
        }
    }

    if (g.win) {
        const text_w = 32;
        const gap = 4;
        // const text_h = 32;
        const letters = [_]?*const Sprite{ &Sprite.text_y, &Sprite.text_o, &Sprite.text_u, null, &Sprite.text_w, &Sprite.text_i, &Sprite.text_n };
        const text_all_w = @as(i32, @intCast(letters.len)) * (text_w + gap) - gap;
        const text_shift_x = @divTrunc(width - text_all_w, 2);
        for (letters, 0..) |sprite, i| {
            if (sprite == null) continue;
            const x = @as(i32, @intCast(i)) * (text_w + gap) + text_shift_x;
            const delta = time / 300 + @as(f32, @floatFromInt(i)) / 2;
            const A = 10;
            const y: i32 = @as(i32, @intFromFloat(@trunc(std.math.sin(delta) * A))) + main_board_y_shift + 200;
            g.canvas.draw_sprite(sprite.?, x, y);
        }
    }

    if (mouse_inside) {
        g.canvas.draw_sprite(&Sprite.cursor, mouse_x, mouse_y);
    }

    g.canvas.end_frame();
    pf.output_image_data(@ptrCast(g.canvas.surf.pixels));
}
