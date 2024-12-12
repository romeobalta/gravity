const std = @import("std");
const ray = @import("raylib.zig");

const ArrayList = std.ArrayList;
const Vector2 = ray.struct_Vector2;
const Rectangle = ray.struct_Rectangle;

const WIDTH: f32 = 800;
const HEIGHT: f32 = 600;

const TIME_PER_UPDATE: f32 = @as(f32, 1.0 / 60.0);

const G = 9.8;

const PADDLE_WIDTH: f32 = 10;
const PADDLE_HEIGHT: f32 = 60;

const PLAYER_SPEED: f32 = 5.0;
const PLAYER_COOLDOWN: f32 = 0.5;

const Player = struct {
    rectangle: Rectangle,
    color: ray.struct_Color,
    charge: f32 = 0.0,
    cooldown: f32 = PLAYER_COOLDOWN,
    direction: Vector2 = .{ .x = 1, .y = 0 },

    fn player1() Player {
        return .{
            .rectangle = .{
                .x = 5.0,
                .y = HEIGHT / 2,
                .width = PADDLE_WIDTH,
                .height = PADDLE_HEIGHT,
            },
            .color = ray.BLUE,
        };
    }

    fn player2() Player {
        return .{
            .rectangle = .{
                .x = WIDTH - 5.0 - PADDLE_WIDTH,
                .y = HEIGHT / 2,
                .width = PADDLE_WIDTH,
                .height = PADDLE_HEIGHT,
            },
            .color = ray.ORANGE,
        };
    }

    fn getShootingPosition(self: *@This()) f32 {
        return if (self.rectangle.x < WIDTH / 2) 1 else -1;
    }

    fn draw(self: *const @This()) void {
        ray.DrawRectangleRec(self.rectangle, self.color);

        ray.DrawCircleV(.{ .x = self.rectangle.x, .y = 40 }, self.charge, self.color);
    }

    fn update(self: *@This()) void {
        if (self.cooldown <= 0 and self.charge < Projectile.MAX_SIZE) {
            self.charge += 0.1;
        }
        if (self.cooldown > 0) {
            self.cooldown -= TIME_PER_UPDATE;
        }
    }

    fn move(self: *@This(), velocity: Vector2) void {
        const new_pos = ray.Vector2Add(.{ .x = self.rectangle.x, .y = self.rectangle.y }, velocity);
        self.rectangle.x = new_pos.x;
        self.rectangle.y = new_pos.y;
    }

    fn shoot(self: *@This(), projectiles: *ArrayList(Projectile)) !void {
        if (self.charge >= Projectile.MIN_SIZE) {
            try projectiles.append(Projectile.init(self));
            self.charge = 0;
            self.cooldown = PLAYER_COOLDOWN;
        }
    }
};

const Projectile = struct {
    position: Vector2 = .{ .x = 0, .y = 0 },
    radius: f32 = 1,
    velocity: Vector2 = .{ .x = 0, .y = 0 },
    player: *Player,
    forces: Vector2 = .{ .x = 0, .y = 0 },
    to_delete: bool = false,

    const MIN_SIZE: f32 = 1.0;
    const MAX_SIZE: f32 = 20.0;

    const MIN_VELOCITY: f32 = 2.0;
    const MAX_VELOCITY: f32 = 7.0;

    const MAX_DISTANCE_GRAVITY: f32 = 100;

    fn init(player: *Player) Projectile {
        std.debug.print("{d}\n", .{player.charge});
        return .{
            .position = ray.Vector2Add(.{
                .x = player.rectangle.x,
                .y = player.rectangle.y,
            }, .{
                .y = PADDLE_HEIGHT / 2,
                .x = (PADDLE_WIDTH + player.charge + 10) * player.getShootingPosition(),
            }),
            .radius = player.charge,
            .velocity = ray.Vector2Scale(player.direction, calculateVelocity(player.charge)),
            .player = player,
        };
    }

    fn calculateVelocity(size: f32) f32 {
        const rate = (size - MIN_SIZE) / (MAX_SIZE - MIN_SIZE);
        return MAX_VELOCITY - rate * (MAX_VELOCITY - MIN_VELOCITY);
    }

    fn draw(self: *const @This()) void {
        ray.DrawCircleV(self.position, self.radius, self.player.color);
        // ray.DrawLineV(self.position, ray.Vector2Add(self.position, ray.Vector2Scale(self.forces, 1000)), self.player.color);
    }

    fn update(self: *@This()) void {
        self.velocity = ray.Vector2Add(self.velocity, self.forces);
        self.position = ray.Vector2Add(self.position, self.velocity);
        self.forces = ray.Vector2Zero();
    }

    fn checkProjectileCollision(self: *@This(), target: *@This()) bool {
        return ray.CheckCollisionCircles(self.position, self.radius, target.position, target.radius);
    }

    fn checkPlayerCollision(self: *@This(), player: *Player) void {
        if (ray.CheckCollisionCircleRec(self.position, self.radius, player.rectangle)) {
            self.velocity.x *= -1;
            self.player = player;
        }
    }

    fn checkOutOfBounds(self: *@This()) bool {
        if (self.position.y - self.radius <= 0 or self.position.y + self.radius >= HEIGHT) {
            self.velocity.y *= -1;
        }

        if (self.position.x - self.radius <= 0 or self.position.x + self.radius >= WIDTH) {
            return true;
        }

        return false;
    }

    fn computeGravity(self: *@This(), target: *@This()) void {
        const distance = ray.Vector2Distance(self.position, target.position);
        const gravity = (G * self.radius * target.radius * 10) / (distance * distance);

        const direction = ray.Vector2Normalize(ray.Vector2Subtract(self.position, target.position));
        std.debug.print("gravity: {d}\n", .{gravity});

        self.forces = ray.Vector2Add(self.forces, ray.Vector2Negate(ray.Vector2Scale(direction, gravity / self.radius)));
        // self.forces = ray.Vector2Negate(ray.Vector2Scale(direction, gravity / self.size));
        // std.debug.print("self: {any}\n", .{self.forces});
        target.forces = ray.Vector2Add(target.forces, ray.Vector2Scale(direction, gravity / target.radius));
        // target.forces = ray.Vector2Scale(direction, gravity / target.size);
        // std.debug.print("target: {any}\n", .{target.forces});
    }

    fn addImpulse(self: *@This(), target: *@This()) void {
        _ = self;
        _ = target;
    }
};

pub fn main() !void {
    ray.InitWindow(WIDTH, HEIGHT, "gravity");
    defer ray.CloseWindow();

    var time_since_last_update: f32 = 0;

    var player1 = Player.player1();
    var player2 = Player.player2();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var projectiles: ArrayList(Projectile) = ArrayList(Projectile).init(allocator);
    defer projectiles.deinit();

    while (!ray.WindowShouldClose()) {
        time_since_last_update += ray.GetFrameTime();

        var do_post_update = false;
        // update
        if (time_since_last_update > TIME_PER_UPDATE) {
            time_since_last_update = 0;
            do_post_update = true;

            if (ray.IsKeyDown(ray.KEY_DOWN)) {
                player1.move(.{ .y = 1 * PLAYER_SPEED });
            } else if (ray.IsKeyDown(ray.KEY_UP)) {
                player1.move(.{ .y = -1 * PLAYER_SPEED });
            }

            if (ray.IsKeyDown(ray.KEY_F)) {
                try player1.shoot(&projectiles);
            }

            for (projectiles.items, 0..) |*projectile, i| {
                for (projectiles.items, 0..) |*target, j| {
                    if (i >= j) continue;

                    if (projectile.checkProjectileCollision(target)) {
                        if (projectile.radius == target.radius) {
                            projectile.to_delete = true;
                            target.to_delete = true;
                        }
                        if (projectile.radius > target.radius) {
                            target.to_delete = true;
                            projectile.addImpulse(target);
                        } else {
                            projectile.to_delete = true;
                            target.addImpulse(projectile);
                        }
                        continue;
                    }

                    projectile.computeGravity(target);
                    std.debug.print("calculating {d} {d}\n", .{ i, j });
                }

                if (projectile.checkOutOfBounds()) {
                    projectile.to_delete = true;
                    continue;
                }

                projectile.checkPlayerCollision(&player1);
                projectile.checkPlayerCollision(&player2);

                projectile.update();
            }

            var i = projectiles.items.len;
            while (i > 0) : (i -= 1) {
                if (projectiles.items[i - 1].to_delete) {
                    std.debug.print("delete {d} total {d}", .{ i - 1, projectiles.items.len });
                    _ = projectiles.orderedRemove(i - 1);
                }
            }

            player1.update();
            player2.update();
        }

        // drawing
        {
            ray.BeginDrawing();
            defer ray.EndDrawing();

            ray.ClearBackground(ray.BLACK);
            ray.DrawFPS(10, 10);

            for (projectiles.items) |projectile| {
                projectile.draw();
            }

            player1.draw();
            player2.draw();
        }
    }
}

test "simple test" {}
