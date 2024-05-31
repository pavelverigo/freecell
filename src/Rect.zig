x: i32,
y: i32,
w: i32,
h: i32,

const Rect = @This();

pub fn from_wh(w: i32, h: i32) Rect {
    return .{ .x = 0, .y = 0, .w = w, .h = h };
}

pub fn intersect(a: Rect, b: Rect) Rect {
    const x1 = @max(a.x, b.x);
    const y1 = @max(a.y, b.y);
    const x2 = @min(a.x + a.w, b.x + b.w);
    const y2 = @min(a.y + a.h, b.y + b.h);
    return .{ .x = x1, .y = y1, .w = x2 - x1, .h = y2 - y1 };
}

pub fn inset(r: Rect, dx: i32, dy: i32) Rect {
    return .{ .x = r.x + dx, .y = r.y + dy, .w = r.w - 2 * dx, .h = r.h - 2 * dy };
}

pub fn offset(r: Rect, dx: i32, dy: i32) Rect {
    return .{ .x = r.x + dx, .y = r.y + dy, .w = r.w, .h = r.h };
}

pub fn is_empty(r: Rect) bool {
    return r.w <= 0 or r.h <= 0;
}

pub fn inside(r: Rect, x: i32, y: i32) bool {
    return r.x <= x and x < (r.x + r.w) and r.y <= y and y < (r.y + r.h);
}

pub fn area(r: Rect) i64 {
    return if (!r.is_empty()) r.w * r.h else 0;
}
