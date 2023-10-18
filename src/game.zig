const wasm = @import("wasm.zig");
const d2 = @import("d2.zig");
const std = @import("std");

var canvas: d2.Canvas = undefined;

const Card = struct {
    pub const Suit = enum {
        diamonds,
        hearts,
        clubs,
        spades,

        fn isBlack(s: Suit) bool {
            return s == .clubs or s == .spades;
        }

        fn isRed(s: Suit) bool {
            return s == .diamonds or s == .hearts;
        }

        fn isOpposite(s1: Suit, s2: Suit) bool {
            return s1.isBlack() != s2.isBlack();
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
    };

    suit: Suit,
    rank: Rank,
};

fn viableForFoundation(card: Card, n_top_rank: ?Card.Rank, suit: Card.Suit) bool {
    if (card.suit != suit) return false;
    if (n_top_rank) |top_rank| {
        return @intFromEnum(card.rank) - @intFromEnum(top_rank) == 1;
    } else {
        return card.rank == .a;
    }
}

fn viableForCascade(card: Card, n_top: ?Card) bool {
    if (n_top) |top| {
        return card.suit.isOpposite(top.suit) and @intFromEnum(top.rank) - @intFromEnum(card.rank) == 1;
    } else {
        return true;
    }
}

pub fn cardToSprite(card: Card) d2.Sprites {
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

const card_w = 88;
const card_h = 124;

// Called once
pub fn init(main_image: d2.Image) void {
    resetGame();
    canvas = .{
        .backed_image = main_image,
    };
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
        return .{ .x = x1, .y = y1, .w = x2 - x1, .h = y2 - y1 };
    }

    pub fn isEmpty(r: RectRegion) bool {
        return r.w <= 0 or r.h <= 0;
    }

    pub fn area(r: RectRegion) i64 {
        return r.w * r.h;
    }
};

fn resetGame() void {
    open_slots = .{ null, null, null, null };
    foundations = std.EnumArray(Card.Suit, ?Card.Rank).initFill(null);

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

    var prng = std.rand.DefaultPrng.init(wasm.seed());
    var random = prng.random();
    random.shuffle(Card, &deck);

    cascades = .{
        std.BoundedArray(Card, 24).fromSlice(deck[0..7]) catch unreachable,
        std.BoundedArray(Card, 24).fromSlice(deck[7..14]) catch unreachable,
        std.BoundedArray(Card, 24).fromSlice(deck[14..21]) catch unreachable,
        std.BoundedArray(Card, 24).fromSlice(deck[21..28]) catch unreachable,
        std.BoundedArray(Card, 24).fromSlice(deck[28..34]) catch unreachable,
        std.BoundedArray(Card, 24).fromSlice(deck[34..40]) catch unreachable,
        std.BoundedArray(Card, 24).fromSlice(deck[40..46]) catch unreachable,
        std.BoundedArray(Card, 24).fromSlice(deck[46..52]) catch unreachable,
    };
}

fn dragCards(pos: CardPosition) std.BoundedArray(Card, 16) {
    var cards = std.BoundedArray(Card, 16).init(0) catch unreachable;
    switch (pos) {
        .open_slot => |i| {
            cards.append(open_slots[i].?) catch unreachable;
        },
        .cascade => |cpos| {
            const cascade = cascades[cpos.column];
            var j: usize = @intCast(cpos.row);
            const len: usize = @intCast(cascade.len);
            while (j < len) {
                cards.append(cascade.get(j)) catch unreachable;
                j += 1;
            }
        },
    }
    return cards;
}

fn removeDragCards(pos: CardPosition) void {
    switch (pos) {
        .open_slot => |i| {
            open_slots[i] = null;
        },
        .cascade => |cpos| {
            cascades[cpos.column].resize(cpos.row) catch unreachable;
        },
    }
}

var open_slots: [4]?Card = undefined;
var foundations: std.EnumArray(Card.Suit, ?Card.Rank) = undefined;
var cascades: [8]std.BoundedArray(Card, 24) = undefined;

var drag_card_offset_x: i32 = 0;
var drag_card_offset_y: i32 = 0;

const CascadePos = struct {
    column: u8,
    row: u8,
};

const CardPosition = union(enum) {
    open_slot: u8,
    cascade: CascadePos,
};

var dragging_pos: ?CardPosition = null;
var pressed_prev: bool = false;

pub fn frame(mx: i32, my: i32, inside: bool, pressed: bool) void {
    const BOARD_COLOR: d2.RGBA = .{ .r = 0x00, .g = 0x80, .b = 0x00, .a = 0xFF };
    const HIGHLIGHT_COLOR: d2.RGBA = .{ .r = 0x00, .g = 0x50, .b = 0x00, .a = 0xFF };

    const width = canvas.width();
    const height = canvas.height();

    const card_x_gap = 20;
    const card_y_shift = 30;

    const main_board_y_shift = 180;
    const main_board_width = 8 * card_w + (8 - 1) * card_x_gap;
    const main_board_x_shift = @divTrunc(width - main_board_width, 2);

    const top_line_x = main_board_x_shift;
    const top_line_y = 20;

    const clicked = !pressed_prev and pressed;
    pressed_prev = pressed;

    if (clicked) {
        _ = blk: {
            for (0..4) |i| {
                if (open_slots[i] == null) continue;
                const x = @as(i32, @intCast(i)) * (card_w + card_x_gap) + top_line_x;
                const y = top_line_y;

                const region: RectRegion = .{ .x = x, .y = y, .w = card_w, .h = card_h };
                if (region.inside(mx, my)) {
                    drag_card_offset_x = mx - region.x;
                    drag_card_offset_y = my - region.y;

                    dragging_pos = .{ .open_slot = @intCast(i) };

                    break :blk;
                }
            }
            for (cascades, 0..) |cascade, i| {
                if (cascade.len == 0) continue;

                const j = cascade.len - 1;
                // const last_card = cascade.get(j);

                const x = @as(i32, @intCast(i)) * (card_w + card_x_gap) + main_board_x_shift;
                const y = @as(i32, @intCast(j)) * card_y_shift + main_board_y_shift;
                const region: RectRegion = .{ .x = x, .y = y, .w = card_w, .h = card_h };
                if (region.inside(mx, my)) {
                    drag_card_offset_x = mx - region.x;
                    drag_card_offset_y = my - region.y;

                    dragging_pos = .{ .cascade = .{ .column = @intCast(i), .row = @intCast(j) } };

                    break :blk;
                }
            }
        };
    }
    if (!pressed) {
        if (dragging_pos) |pos| blk: {
            const moving_cards = dragCards(pos);
            const card_off_x = mx - drag_card_offset_x;
            const card_off_y = my - drag_card_offset_y;
            const draggin_rect: RectRegion = .{ .x = card_off_x, .y = card_off_y, .w = card_w, .h = card_h };

            if (moving_cards.len == 1) {
                for (0..4) |i| {
                    if (open_slots[i] != null) continue;
                    const x = @as(i32, @intCast(i)) * (card_w + card_x_gap) + top_line_x;
                    const y = top_line_y;

                    const region: RectRegion = .{ .x = x, .y = y, .w = card_w, .h = card_h };
                    const res_region = region.intersect(draggin_rect);
                    if (!res_region.isEmpty()) {
                        if (2 * res_region.area() >= card_w * card_h) {
                            open_slots[i] = moving_cards.get(0);
                            removeDragCards(pos);
                            break :blk;
                        }
                    }
                }

                for (std.enums.values(Card.Suit), 0..) |suit, i| {
                    const x = @as(i32, @intCast(i)) * (card_w + card_x_gap) + top_line_x;
                    const y = top_line_y;

                    const region: RectRegion = .{ .x = x, .y = y, .w = card_w, .h = card_h };
                    const res_region = region.intersect(draggin_rect);
                    if (!res_region.isEmpty()) {
                        if (2 * res_region.area() >= card_w * card_h) {
                            if (viableForFoundation(moving_cards.get(0), foundations.get(suit), suit)) {
                                foundations.set(suit, moving_cards.get(0));
                                removeDragCards(pos);
                                break :blk;
                            }
                        }
                    }
                }
            }

            for (cascades, 0..) |cascade, i| {
                if (pos == .cascade and pos.cascade.column == i) continue;

                const x = @as(i32, @intCast(i)) * (card_w + card_x_gap) + main_board_x_shift;
                const y = main_board_y_shift;
                const region: RectRegion = .{ .x = x, .y = y, .w = card_w, .h = height - main_board_y_shift };
                const res_region = region.intersect(draggin_rect);
                if (!res_region.isEmpty()) {
                    if (2 * res_region.area() >= card_w * card_h) {
                        const n_top: ?Card = if (cascade.len == 0) null else cascade.get(cascade.len - 1);
                        if (viableForCascade(moving_cards.get(0), n_top)) {
                            for (moving_cards.slice()) |card| {
                                cascades[i].append(card) catch unreachable;
                            }
                            removeDragCards(pos);
                            break :blk;
                        }
                    }
                }
            }
        }

        dragging_pos = null;
    }

    canvas.drawColor(BOARD_COLOR);

    const nij: ?CascadePos = blk: {
        if (dragging_pos) |pos| {
            break :blk switch (pos) {
                .cascade => |val| val,
                else => null,
            };
        } else {
            break :blk null;
        }
    };

    for (cascades, 0..) |cascade, i| {
        for (cascade.slice(), 0..) |card, j| {
            if (nij) |ij| if (ij.column == i and ij.row <= j) break;
            const x = @as(i32, @intCast(i)) * (card_w + card_x_gap) + main_board_x_shift;
            const y = @as(i32, @intCast(j)) * card_y_shift + main_board_y_shift;
            canvas.drawSprite(x, y, cardToSprite(card));
        }
    }

    for (0..4) |i| {
        const x = @as(i32, @intCast(i)) * (card_w + card_x_gap) + top_line_x;
        const y = top_line_y;
        canvas.drawRect(x, y, card_w, card_h, HIGHLIGHT_COLOR);
    }

    for (0..4) |i| {
        if (dragging_pos) |pos| if (pos == .open_slot and pos.open_slot == i) continue;
        if (open_slots[i]) |card| {
            const x = @as(i32, @intCast(i)) * (card_w + card_x_gap) + top_line_x;
            const y = top_line_y;
            canvas.drawSprite(x, y, cardToSprite(card));
        }
    }

    for (4..8) |i| {
        const x = @as(i32, @intCast(i)) * (card_w + card_x_gap) + top_line_x;
        const y = top_line_y;
        canvas.drawRect(x, y, card_w, card_h, HIGHLIGHT_COLOR);
    }

    {
        var cards = std.BoundedArray(Card, 24).init(0) catch unreachable;
        if (dragging_pos) |pos| {
            switch (pos) {
                .open_slot => |i| {
                    cards.append(open_slots[i].?) catch unreachable;
                },
                .cascade => |cpos| {
                    const i: usize = cpos.column;
                    const cascade = cascades[i];
                    var j: usize = cpos.row;
                    const cascade_size: usize = @intCast(cascade.len);
                    while (j < cascade_size) {
                        cards.append(cascade.get(j)) catch unreachable;
                        j += 1;
                    }
                },
            }
        }

        const card_off_x = mx - drag_card_offset_x;
        const card_off_y = my - drag_card_offset_y;

        for (cards.slice(), 0..) |card, j| {
            const x = card_off_x;
            const y = @as(i32, @intCast(j)) * card_y_shift + card_off_y;
            canvas.drawSprite(x, y, cardToSprite(card));
        }
    }

    if (inside) {
        canvas.drawRect(mx - 5, my - 5, 10, 10, d2.RGBA.BLACK);
    }

    canvas.finalize();
}
