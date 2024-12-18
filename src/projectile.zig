const std = @import("std");
const ray = @import("raylib.zig");
const root = @import("main.zig");
const Player = @import("player.zig").Player;
const Particle = @import("particle.zig").Particle;

const WIDTH = root.WIDTH;
const HEIGHT = root.HEIGHT;
const G = root.G;

const ArrayList = std.ArrayList;
const Rectangle = ray.Rectangle;
const Vector2 = ray.Vector2;

pub const Projectile = struct {
    position: Vector2 = .{ .x = 0, .y = 0 },
    radius: f32 = 1,
    velocity: Vector2 = .{ .x = 0, .y = 0 },
    player: *Player,
    forces: Vector2 = .{ .x = 0, .y = 0 },
    to_delete: bool = false,
    tail: ArrayList(Particle),

    pub const MIN_SIZE: f32 = 5.0;
    pub const MAX_SIZE: f32 = 20.0;

    pub const MIN_VELOCITY: f32 = 1.0;
    pub const MAX_VELOCITY: f32 = 8.0;

    pub const MAX_DISTANCE_GRAVITY: f32 = 100;

    pub fn init(player: *Player, allocator: std.mem.Allocator) Projectile {
        const position_multiplier: f32 = switch (player.side) {
            .Left => 1,
            .Right => -1,
        };

        return .{
            .position = ray.Vector2Add(.{
                .x = player.rectangle.x,
                .y = player.rectangle.y,
            }, .{
                .y = Player.PADDLE_HEIGHT / 2,
                .x = (Player.PADDLE_WIDTH + player.charge + 10) * position_multiplier,
            }),
            .radius = player.charge,
            .velocity = ray.Vector2Scale(player.direction, calculate_velocity(player.charge)),
            .player = player,
            .tail = ArrayList(Particle).init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.tail.clearAndFree();
        self.tail.deinit();
    }

    fn calculate_velocity(size: f32) f32 {
        return ray.Remap(size, MIN_SIZE, MAX_SIZE, MAX_VELOCITY, MIN_VELOCITY);
    }

    pub fn draw(self: *const @This()) void {
        for (self.tail.items) |particle| {
            particle.draw();
        }

        ray.DrawCircleV(self.position, self.radius, self.player.color);
    }

    pub fn update(self: *@This()) void {
        self.velocity = ray.Vector2Add(self.velocity, self.forces);
        self.position = ray.Vector2Add(self.position, self.velocity);
        self.forces = ray.Vector2Zero();

        {
            var i = self.tail.items.len;
            while (i > 0) : (i -= 1) {
                const index = i - 1;
                var particle = &self.tail.items[index];

                particle.update();

                if (particle.size <= 0) {
                    _ = self.tail.orderedRemove(index);
                }
            }
        }
    }

    pub fn check_projectile_collision(self: *@This(), target: *@This()) bool {
        const distance = ray.Vector2Distance(self.position, target.position);
        return distance <= (self.radius + target.radius);
    }

    pub fn check_player_collision(self: *@This(), player: *Player) void {
        if (ray.CheckCollisionCircleRec(self.position, self.radius, player.rectangle)) {
            self.velocity.x *= -1;
            self.player = player;
        }
    }

    pub fn check_out_of_bounds(self: *@This()) bool {
        if (self.position.y - self.radius <= 0 or self.position.y + self.radius >= HEIGHT) {
            self.velocity.y *= -1;
        }

        if (self.position.x - self.radius <= 0 or self.position.x + self.radius >= WIDTH) {
            return true;
        }

        return false;
    }

    pub fn compute_gravity(self: *@This(), target: *@This()) void {
        const distance = ray.Vector2Distance(self.position, target.position);
        const gravity = (G * self.radius * target.radius * 50) / (distance * distance);

        const direction = ray.Vector2Normalize(ray.Vector2Subtract(self.position, target.position));

        const selfGravity = if (self.radius > target.radius) gravity / (self.radius * 10) else gravity / self.radius;
        const targetGravity = if (self.radius < target.radius) gravity / (target.radius * 10) else gravity / target.radius;

        self.forces = ray.Vector2Add(self.forces, ray.Vector2Negate(ray.Vector2Scale(direction, selfGravity)));
        target.forces = ray.Vector2Add(target.forces, ray.Vector2Scale(direction, targetGravity));
    }

    pub fn consume(self: *@This(), target: *@This()) void {
        const size_diff = self.radius - target.radius;
        const min_size_diff = 0;
        const max_size_diff = MAX_SIZE - MIN_SIZE;
        const min_impact = 0.1;
        const max_impact = 0.99;
        const impact = ray.Remap(size_diff, min_size_diff, max_size_diff, max_impact, min_impact);

        self.forces = ray.Vector2Add(self.forces, ray.Vector2Scale(target.velocity, impact * impact));

        // TODO: add extra radius to mass
        const new_radius = ray.Clamp(self.radius + target.radius, MIN_SIZE, MAX_SIZE);
        self.radius = new_radius;
    }
};
