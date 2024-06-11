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

// Raw freecell state
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

const canvas_w = 1200;
const canvas_h = 900;

const char_w = 10;
const char_h = 22;
const char_dx = 4;
const btn_h = char_h + 12;
const btn_x_shift = 20;
const btn_y = canvas_h - btn_h - 20;

const new_game_btn_rect = Rect.from_wh(200, btn_h).offset(btn_x_shift, btn_y);
const restart_game_btn_rect = Rect.from_wh(200, btn_h).offset(2 * btn_x_shift + 200, btn_y);
const highlight_mode_btn_rect = Rect.from_wh(300, btn_h).offset(3 * btn_x_shift + 200 + 200, btn_y);

const main_board_y_shift = 180;
const main_board_width = 8 * card_w + (8 - 1) * card_x_gap;

const main_board_x_shift = @divTrunc(canvas_w - main_board_width, 2);

const animation_time = 300; // ms

const card_w = 88;
const card_h = 124;
const card_x_gap = 20;
const card_y_shift = 30;

const top_line_y = 20;

pub fn frame(g: *Game) void {
    const mouse_x = pf.get_mouse_x();
    const mouse_y = pf.get_mouse_y();
    const mouse_inside = pf.is_mouse_inside();
    const main_button_down = pf.is_mouse_button_down(.main);
    const time = pf.get_timestamp();

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
                    const card_region = cardRegionFromPos(pos);
                    g.drag = .{
                        .offset_x = mouse_x - card_region.x,
                        .offset_y = mouse_y - card_region.y,
                        .top_card_pos = pos,
                    };
                }
            }
            if (new_game_btn_rect.inside(mouse_x, mouse_y)) {
                g.start_new_game();
            }
            if (restart_game_btn_rect.inside(mouse_x, mouse_y)) {
                g.restart_game();
            }
            if (highlight_mode_btn_rect.inside(mouse_x, mouse_y)) {
                g.highlight_moves = !g.highlight_moves;
            }
        }

        if (!main_button_down) {
            if (g.drag) |d| make_move: {
                const card_region: Rect = .{ .x = mouse_x - d.offset_x, .y = mouse_y - d.offset_y, .w = card_w, .h = card_h };
                const to = cardDropPos(card_region) orelse break :make_move;
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

    g.canvas.begin_frame();

    const BOARD_COLOR: d2.RGBA = .{ .r = 0x00, .g = 0x80, .b = 0x00, .a = 0xFF };
    const MAIN_BOARD_COLOR: d2.RGBA = .{ .r = 0x00, .g = 0x70, .b = 0x00, .a = 0xFF };
    const HIGHLIGHT_COLOR: d2.RGBA = .{ .r = 0x00, .g = 0x50, .b = 0x00, .a = 0xFF };
    const LIGHT_HIGHLIGHT_COLOR: d2.RGBA = .{ .r = 0x00, .g = 0xD7, .b = 0x00, .a = 0xFF };
    const GOLD_COLOR: d2.RGBA = .{ .r = 0xFF, .g = 0xD7, .b = 0x00, .a = 0xFF };
    const NON_MOVABLE_MASK_COLOR: d2.RGBA = .{ .r = 0x00, .g = 0x00, .b = 0x00, .a = 0x80 };
    const BLACK: d2.RGBA = .{ .r = 0x00, .g = 0x00, .b = 0x00, .a = 0xFF };
    const WHITE: d2.RGBA = .{ .r = 0xFF, .g = 0xFF, .b = 0xFF, .a = 0xFF };
    const GRAY: d2.RGBA = .{ .r = 0x80, .g = 0x80, .b = 0x80, .a = 0xFF };

    const main_board_rect: Rect = .{ .x = main_board_x_shift, .y = main_board_y_shift, .w = main_board_width, .h = canvas_h - main_board_y_shift - 120 };

    g.canvas.draw_rect(Rect.from_wh(canvas_w, canvas_h), BOARD_COLOR);

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
                    g.canvas.draw_rect(Rect.from_wh(card_w, card_h).offset(x, y), NON_MOVABLE_MASK_COLOR);
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
        const x = @as(i32, @intCast(i)) * (card_w + card_x_gap) + main_board_rect.x;
        const y = top_line_y;
        g.canvas.draw_rect(Rect.from_wh(card_w, card_h).offset(x, y).inset(-1, -1), LIGHT_HIGHLIGHT_COLOR);
        g.canvas.draw_rect(Rect.from_wh(card_w, card_h).offset(x, y), HIGHLIGHT_COLOR);
    }

    for (0..4) |i| {
        if (g.drag) |d| if (d.top_card_pos == .open_slot and d.top_card_pos.open_slot == i) continue;
        if (g.animation) |anim| if (anim.from == .open_slot and anim.from.open_slot == i) continue;
        if (g.freecell.open_slots[i]) |card| {
            const x = @as(i32, @intCast(i)) * (card_w + card_x_gap) + main_board_rect.x;
            const y = top_line_y;
            g.canvas.draw_sprite(sprite_from_card(card), x, y);
        }
    }

    for (4..8) |i| {
        const x = @as(i32, @intCast(i)) * (card_w + card_x_gap) + main_board_rect.x;
        const y = top_line_y;
        g.canvas.draw_rect(Rect.from_wh(card_w, card_h).offset(x, y).inset(-1, -1), GOLD_COLOR);
        g.canvas.draw_rect(Rect.from_wh(card_w, card_h).offset(x, y), HIGHLIGHT_COLOR);
    }

    for (std.enums.values(Card.Suit), 0..) |suit, i| {
        const x = @as(i32, @intCast(i + 4)) * (card_w + card_x_gap) + main_board_rect.x;
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
                const x = @as(i32, @intCast(i)) * (card_w + card_x_gap) + main_board_rect.x;
                const y = top_line_y;
                break :blk .{ .x = x, .y = y, .w = card_w, .h = card_h };
            },
            .foundation => unreachable,
        };
        const to_region: Rect = rect: {
            const i: i32 = @intFromEnum(card.suit);
            const x = (i + 4) * (card_w + card_x_gap) + main_board_rect.x;
            const y = top_line_y;
            break :rect .{ .x = x, .y = y, .w = card_w, .h = card_h };
        };

        const t = (time - anim.begin_time) / animation_time;
        const x: i32 = @intFromFloat(@floor(std.math.lerp(@as(f32, @floatFromInt(from_region.x)), @as(f32, @floatFromInt(to_region.x)), t)));
        const y: i32 = @intFromFloat(@floor(std.math.lerp(@as(f32, @floatFromInt(from_region.y)), @as(f32, @floatFromInt(to_region.y)), t)));
        g.canvas.draw_sprite(sprite_from_card(card), x, y);
    }

    {
        const rect = new_game_btn_rect;
        g.canvas.draw_rect(rect, BLACK);
        const inner_color = if (rect.inside(mouse_x, mouse_y)) GRAY else WHITE;
        g.canvas.draw_rect(rect.inset(2, 2), inner_color);
        const text_region = rect.inset(10, 6);
        d2.draw_monogram_text(&g.canvas, "NEW GAME", text_region.x, text_region.y, 4);
    }
    {
        const rect = restart_game_btn_rect;
        g.canvas.draw_rect(rect, BLACK);
        const inner_color = if (rect.inside(mouse_x, mouse_y)) GRAY else WHITE;
        g.canvas.draw_rect(rect.inset(2, 2), inner_color);
        const text_region = rect.inset(10, 6);
        d2.draw_monogram_text(&g.canvas, "RESTART GAME", text_region.x, text_region.y, 4);
    }
    {
        const rect = highlight_mode_btn_rect;
        g.canvas.draw_rect(rect, BLACK);
        const inner_color = if (rect.inside(mouse_x, mouse_y)) GRAY else WHITE;
        g.canvas.draw_rect(rect.inset(2, 2), inner_color);
        const text_region = rect.inset(10, 6);
        const text = if (g.highlight_moves) "HIGHLIGHT MOVES: ON" else "HIGHLIGHT MOVES: OFF";
        d2.draw_monogram_text(&g.canvas, text, text_region.x, text_region.y, 4);
    }

    if (g.win) {
        const text = "YOU WIN!";
        const text_all_w = text.len * (char_w + 4) - 4;
        const text_shift_x = @divTrunc(canvas_w - text_all_w, 2);

        for (text, 0..) |char, i| {
            const x = @as(i32, @intCast(i)) * (char_w + 4) + text_shift_x;
            const delta = time / 300 + @as(f32, @floatFromInt(i)) / 2;
            const A = 10;
            const y: i32 = @as(i32, @intFromFloat(@trunc(std.math.sin(delta) * A))) + main_board_y_shift + 200;
            const color_rot: f64 = @mod((time / 2000) - 1.0 * @as(f64, @floatFromInt(i)) / text.len, 1.0);

            g.canvas.draw_rect(Rect.from_wh(char_w, char_h).offset(x, y).inset(-2, -10), color_circle(color_rot));
            d2.draw_monogram_text(&g.canvas, &.{char}, x, y, 0);
        }
    }

    if (mouse_inside) {
        g.canvas.draw_sprite(&Sprite.cursor, mouse_x, mouse_y);
    }

    g.canvas.end_frame();
    pf.output_image_data(@ptrCast(g.canvas.surf.pixels));
}

fn color_circle(rot: f64) d2.RGBA {
    std.debug.assert(0.0 <= rot and rot < 1.0);
    const sector = 1.0 / 6.0;
    if (rot < 1 * sector) {
        const v: u8 = @intFromFloat(255 * (6 * rot - 0));
        return .{ .r = 0xFF, .g = 0x00, .b = v, .a = 0xFF };
    }
    if (rot < 2 * sector) {
        const v: u8 = @intFromFloat(255 * (6 * rot - 1));
        return .{ .r = 0xFF - v, .g = 0x00, .b = 0xFF, .a = 0xFF };
    }
    if (rot < 3 * sector) {
        const v: u8 = @intFromFloat(255 * (6 * rot - 2));
        return .{ .r = 0x00, .g = v, .b = 0xFF, .a = 0xFF };
    }
    if (rot < 4 * sector) {
        const v: u8 = @intFromFloat(255 * (6 * rot - 3));
        return .{ .r = 0x00, .g = 0xFF, .b = 0xFF - v, .a = 0xFF };
    }
    if (rot < 5 * sector) {
        const v: u8 = @intFromFloat(255 * (6 * rot - 4));
        return .{ .r = v, .g = 0xFF, .b = 0x00, .a = 0xFF };
    }
    if (rot < 6 * sector) {
        const v: u8 = @intFromFloat(255 * (6 * rot - 5));
        return .{ .r = 0xFF, .g = 0xFF - v, .b = 0x00, .a = 0xFF };
    }
    unreachable;
}

fn cardDropPos(card_region: Rect) ?Freecell.CardPos { // card position, ignore cascade row
    var best_area: i64 = 0; // search of best intersection
    var best_pos: ?Freecell.CardPos = null;
    for (0..4) |i| { // open slots
        const x = @as(i32, @intCast(i)) * (card_w + card_x_gap) + main_board_x_shift;
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
        const intersect_area = card_region.intersect(.{ .x = x, .y = y, .w = card_w, .h = canvas_h - main_board_y_shift }).area();
        if (intersect_area > best_area) {
            best_area = intersect_area;
            best_pos = .{ .cascade = .{ @intCast(i), 0 } };
        }
    }
    for (0..4) |i| { // foundation
        const x = @as(i32, @intCast(i + 4)) * (card_w + card_x_gap) + main_board_x_shift;
        const y = top_line_y;
        const intersect_area = card_region.intersect(.{ .x = x, .y = y, .w = card_w, .h = card_h }).area();
        if (intersect_area > best_area) {
            best_area = intersect_area;
            best_pos = .{ .foundation = @intCast(i) };
        }
    }
    return best_pos;
}

fn cardRegionFromPos(pos: Freecell.CardPos) Rect {
    switch (pos) {
        .cascade => |ij| {
            const i = ij[0];
            const j = ij[1];
            const x = @as(i32, @intCast(i)) * (card_w + card_x_gap) + main_board_x_shift;
            const y = @as(i32, @intCast(j)) * card_y_shift + main_board_y_shift;
            return .{ .x = x, .y = y, .w = card_w, .h = card_h };
        },
        .open_slot => |i| {
            const x = @as(i32, @intCast(i)) * (card_w + card_x_gap) + main_board_x_shift;
            const y = top_line_y;
            return .{ .x = x, .y = y, .w = card_w, .h = card_h };
        },
        .foundation => |i| {
            const x = @as(i32, @intCast(i + 4)) * (card_w + card_x_gap) + main_board_x_shift;
            const y = top_line_y;
            return .{ .x = x, .y = y, .w = card_w, .h = card_h };
        },
    }
}

fn cardClickPos(g: *Game, click_x: i32, click_y: i32) ?Freecell.CardPos { // card position
    for (0..4) |i| { // open slots
        const x = @as(i32, @intCast(i)) * (card_w + card_x_gap) + main_board_x_shift;
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
