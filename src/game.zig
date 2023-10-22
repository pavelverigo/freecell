const wasm = @import("wasm.zig");
const d2 = @import("d2.zig");
const std = @import("std");

var game: App = undefined;

// Called once
pub fn init(main_image: d2.Image) void {
    game = App.init(main_image);
}

// Called every frame
pub fn frame(mouse_x: i32, mouse_y: i32, mouse_inside: bool, mouse_pressed: bool) void {
    game.frame(mouse_x, mouse_y, mouse_inside, mouse_pressed);
}

const Card = struct {
    pub const Suit = enum(u8) {
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

    pub const Rank = enum(u8) {
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

    pub fn isMovable(f: *Freecell, pos: CardPos) bool {
        switch (pos) {
            .open_slot => return true,
            .foundation => return false,
            .cascade => |ij| {
                const i = ij[0];
                const cascade = f.cascades[i];
                var j = ij[1];
                const len: usize = cascade.len;
                while (j + 1 < len) {
                    const card1 = cascade.get(j);
                    const card2 = cascade.get(j + 1);
                    if (!(card1.suit.isOppositeColor(card2.suit) and card1.rank.diff(card2.rank) == 1)) {
                        return false;
                    }
                    j += 1;
                }
                return true;
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

    pub fn attemptMove(f: *Freecell, from: CardPos, to: CardPos) void { // "to" value cascade row meaningless
        const cards = f.cardsFromPos(from);

        switch (to) { // abort
            .open_slot => |i| {
                if (!(f.open_slots[i] == null and cards.len == 1)) return;
            },
            .foundation => |i| {
                if (cards.len != 1) return;
                const suit: Card.Suit = @enumFromInt(i);
                const card = cards.get(0);
                if (suit != cards.get(0).suit) return;
                if (f.foundations.get(suit)) |rank| {
                    if (card.rank.diff(rank) != 1) return;
                } else {
                    if (card.rank != .a) return;
                }
            },
            .cascade => |ij| {
                const i = ij[0];
                const cascade = f.cascades[i];
                if (cascade.len > 0) {
                    const card1 = cards.get(0);
                    const card2 = cascade.get(cascade.len - 1);

                    if (!(card1.suit.isOppositeColor(card2.suit) and card1.rank.diff(card2.rank) == -1)) return;
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
    canvas: d2.Canvas,
    freecell: Freecell,
    mouse_pressed_prev_frame: bool,
    drag: ?DragState,

    const DragState = struct {
        offset_x: i32,
        offset_y: i32,
        top_card_pos: Freecell.CardPos, // position of card that was moved
    };

    pub fn init(main_image: d2.Image) App {
        return .{
            .canvas = .{ .backed_image = main_image },
            .freecell = Freecell.init(wasm.seed()),
            .mouse_pressed_prev_frame = false,
            .drag = null,
        };
    }

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

    pub fn frame(g: *App, mouse_x: i32, mouse_y: i32, mouse_inside: bool, mouse_pressed: bool) void {
        const clicked = mouse_pressed and !g.mouse_pressed_prev_frame;
        g.mouse_pressed_prev_frame = mouse_pressed;

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
        }

        if (!mouse_pressed) {
            if (g.drag) |d| blk: {
                const card_region: RectRegion = .{ .x = mouse_x - d.offset_x, .y = mouse_y - d.offset_y, .w = card_w, .h = card_h };
                const to = g.cardDropPos(card_region) orelse break :blk;
                g.freecell.attemptMove(d.top_card_pos, to);
            }
            g.drag = null;
        }

        // draw

        const BOARD_COLOR: d2.RGBA = .{ .r = 0x00, .g = 0x80, .b = 0x00, .a = 0xFF };
        const HIGHLIGHT_COLOR: d2.RGBA = .{ .r = 0x00, .g = 0x50, .b = 0x00, .a = 0xFF };

        const width = g.canvas.width();
        const height = g.canvas.height();
        _ = height;
        const main_board_x_shift = @divTrunc(width - main_board_width, 2);
        const top_line_x = main_board_x_shift;

        g.canvas.drawColor(BOARD_COLOR);

        for (g.freecell.cascades, 0..) |cascade, i| {
            for (cascade.slice(), 0..) |card, j| {
                if (g.drag) |d| if (d.top_card_pos == .cascade and d.top_card_pos.cascade[0] == i and d.top_card_pos.cascade[1] == j) break;
                const x = @as(i32, @intCast(i)) * (card_w + card_x_gap) + main_board_x_shift;
                const y = @as(i32, @intCast(j)) * card_y_shift + main_board_y_shift;
                g.canvas.drawSprite(x, y, cardToSprite(card));
            }
        }

        for (0..4) |i| {
            const x = @as(i32, @intCast(i)) * (card_w + card_x_gap) + top_line_x;
            const y = top_line_y;
            g.canvas.drawRect(x, y, card_w, card_h, HIGHLIGHT_COLOR);
        }

        for (0..4) |i| {
            if (g.drag) |d| if (d.top_card_pos == .open_slot and d.top_card_pos.open_slot == i) continue;
            if (g.freecell.open_slots[i]) |card| {
                const x = @as(i32, @intCast(i)) * (card_w + card_x_gap) + top_line_x;
                const y = top_line_y;
                g.canvas.drawSprite(x, y, cardToSprite(card));
            }
        }

        for (4..8) |i| {
            const x = @as(i32, @intCast(i)) * (card_w + card_x_gap) + top_line_x;
            const y = top_line_y;
            g.canvas.drawRect(x, y, card_w, card_h, HIGHLIGHT_COLOR);
        }

        for (std.enums.values(Card.Suit), 0..) |suit, i| {
            const x = @as(i32, @intCast(i + 4)) * (card_w + card_x_gap) + top_line_x;
            const y = top_line_y;

            if (g.freecell.foundations.get(suit)) |rank| {
                g.canvas.drawSprite(x, y, cardToSprite(.{ .suit = suit, .rank = rank }));
            } else {
                g.canvas.drawSprite(x, y, suitToSprite(suit));
            }
        }

        if (g.drag) |d| {
            var cards = g.freecell.cardsFromPos(d.top_card_pos);

            const card_off_x = mouse_x - d.offset_x;
            const card_off_y = mouse_y - d.offset_y;

            for (cards.slice(), 0..) |card, j| {
                const x = card_off_x;
                const y = @as(i32, @intCast(j)) * card_y_shift + card_off_y;
                g.canvas.drawSprite(x, y, cardToSprite(card));
            }
        }

        if (mouse_inside) {
            g.canvas.drawSprite(mouse_x, mouse_y, d2.Sprites.cursor);
        }

        g.canvas.finalize();
    }
};
