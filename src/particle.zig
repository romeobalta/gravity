const std = @import("std");
const ray = @import("raylib.zig");
const root = @import("main.zig");
const color_lib = @import("color.zig");
const Projectile = @import("projectile.zig").Projectile;

const WIDTH = root.WIDTH;
const HEIGHT = root.HEIGHT;

const color_blend = color_lib.color_blend;

const UPDATES_PER_SECOND: f32 = 60;

const ArrayList = std.ArrayList;
const Rectangle = ray.struct_Rectangle;
const Vector2 = ray.struct_Vector2;

pub const Particle = struct {
    position: Vector2,
    size: f32,
    velocity: Vector2 = ray.Vector2Zero(),
    decay_speed: f32 = 0.1,
    color: ray.Color = ray.WHITE,
    projectile: ?*Projectile = null,

    const MIN_SIZE: f32 = 2;
    const MAX_SIZE: f32 = 5;

    pub fn init_debris(position: Vector2, velocity_x: f32, color: ray.Color) @This() {
        const flip: f32 = if (std.Random.boolean(std.crypto.random)) -1 else 1;
        const random = std.Random.float(std.crypto.random, f32); // [0, 1)
        const size = MIN_SIZE + (MAX_SIZE - MIN_SIZE) * random;

        const velocity: Vector2 = .{
            .x = -velocity_x * 0.1,
            .y = std.Random.float(std.crypto.random, f32) * flip,
        };

        return .{
            .position = position,
            .size = size,
            .velocity = ray.Vector2Scale(velocity, 3),
            .color = color,
        };
    }

    pub fn init_trail(projectile: *Projectile) @This() {
        const min_tail_length: f32 = 0;
        const max_tail_length: f32 = 200;
        const min_speed: f32 = 0;
        const max_speed: f32 = 400;

        const speed = ray.Vector2Length(projectile.velocity) * UPDATES_PER_SECOND;
        const tail_length = ray.Remap(speed, min_speed, max_speed, min_tail_length, max_tail_length);
        const tail_duration = tail_length / speed;
        const decay = if (tail_duration > 0) (projectile.radius / tail_duration) / UPDATES_PER_SECOND else projectile.radius;

        const min_color_speed: f32 = 100;
        const blend_amount: u8 = @intFromFloat(ray.Clamp(ray.Remap(
            speed,
            min_color_speed,
            max_speed,
            @as(f32, 200),
            @as(f32, 40),
        ), 40, 200));

        const color = color_blend(projectile.player.color, ray.BLACK, blend_amount);

        return .{
            .position = projectile.position,
            .size = projectile.radius,
            .decay_speed = decay,
            .color = color,
            .projectile = projectile,
        };
    }

    pub fn update(self: *@This()) void {
        self.position = ray.Vector2Add(self.position, self.velocity);
        self.size -= self.decay_speed;
    }

    pub fn draw(self: *const @This()) void {
        ray.DrawCircleV(
            self.position,
            self.size,
            self.color,
        );
    }
};
