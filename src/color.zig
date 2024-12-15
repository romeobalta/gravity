const ray = @import("raylib.zig");

fn component_blend(component: u8, blend: u8, amount: u8) u8 {
    return @intCast((@as(u16, component) * @as(u16, amount) + @as(u16, blend) * (255 - @as(u16, amount))) / 255);
}

pub fn color_blend(color: ray.Color, blend: ray.Color, amount: u8) ray.Color {
    return .{
        .r = component_blend(color.r, blend.r, amount),
        .g = component_blend(color.g, blend.g, amount),
        .b = component_blend(color.b, blend.b, amount),
        .a = color.a,
    };
}
