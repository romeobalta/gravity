const std = @import("std");
const ray = @import("raylib.zig");
const root = @import("main.zig");
const Projectile = @import("projectile.zig").Projectile;

const WIDTH = root.WIDTH;
const HEIGHT = root.HEIGHT;
const TIME_PER_UPDATE = root.TIME_PER_UPDATE;

const ArrayList = std.ArrayList;
const Rectangle = ray.Rectangle;
const Vector2 = ray.Vector2;

const Side = enum {
    Left,
    Right,
};

pub const Player = struct {
    rectangle: Rectangle,
    color: ray.Color,
    charge: f32 = 0.0,
    cooldown: f32 = PLAYER_COOLDOWN,
    direction: Vector2 = .{ .x = 1, .y = 0 },
    life: f32 = 100,
    side: Side,

    pub const PADDLE_WIDTH: f32 = 10;
    pub const PADDLE_HEIGHT: f32 = 100;

    pub const PLAYER_SPEED: f32 = 10;
    pub const PLAYER_COOLDOWN: f32 = 0.5;

    pub fn init_player_1() Player {
        return .{
            .rectangle = .{
                .x = 5.0,
                .y = HEIGHT / 2,
                .width = PADDLE_WIDTH,
                .height = PADDLE_HEIGHT,
            },
            .color = ray.BLUE,
            .side = .Left,
        };
    }

    pub fn init_player_2() Player {
        return .{
            .rectangle = .{
                .x = WIDTH - 5.0 - PADDLE_WIDTH,
                .y = HEIGHT / 2,
                .width = PADDLE_WIDTH,
                .height = PADDLE_HEIGHT,
            },
            .color = ray.ORANGE,
            .side = .Right,
        };
    }

    pub fn draw(self: *const @This(), allocator: std.mem.Allocator) !void {
        ray.DrawRectangleLinesEx(self.rectangle, 1, self.color);

        const charge_height = ray.Remap(self.charge, Projectile.MIN_SIZE, Projectile.MAX_SIZE, 0, self.rectangle.height);
        const charge_rect: ray.Rectangle = .{
            .x = self.rectangle.x,
            .y = self.rectangle.y + (self.rectangle.height - charge_height) / 2,
            .width = self.rectangle.width,
            .height = charge_height,
        };
        ray.DrawRectangleRec(charge_rect, self.color);

        // draw life
        {
            const string = try std.fmt.allocPrintZ(allocator, "Life {d}", .{self.life});
            defer allocator.free(string);

            const font_size: c_int = 30;
            const string_width = ray.MeasureText(string, font_size);
            const position_x: c_int = switch (self.side) {
                .Left => 10,
                .Right => @as(c_int, WIDTH) - string_width - 10,
            };
            ray.DrawText(string, position_x, 10, font_size, self.color);
        }
    }

    pub fn update(self: *@This()) void {
        if (self.cooldown <= 0 and self.charge < Projectile.MAX_SIZE) {
            self.charge += 0.1;
        }
        if (self.cooldown > 0) {
            self.cooldown -= TIME_PER_UPDATE;
        }
    }

    pub fn move(self: *@This(), velocity: Vector2) void {
        var new_pos = ray.Vector2Add(
            .{ .x = self.rectangle.x, .y = self.rectangle.y },
            ray.Vector2Scale(velocity, PLAYER_SPEED),
        );

        if (new_pos.y <= 0) {
            new_pos.y = 0;
        } else if (new_pos.y + self.rectangle.height >= HEIGHT) {
            new_pos.y = HEIGHT - self.rectangle.height;
        }

        self.rectangle.x = new_pos.x;
        self.rectangle.y = new_pos.y;
    }

    pub fn shoot(self: *@This(), allocator: std.mem.Allocator, projectile_list: *ArrayList(Projectile)) !void {
        if (self.cooldown <= 0 and self.charge >= Projectile.MIN_SIZE) {
            try projectile_list.append(Projectile.init(self, allocator));
            self.charge = Projectile.MIN_SIZE;
            self.cooldown = PLAYER_COOLDOWN;
        }
    }
};
