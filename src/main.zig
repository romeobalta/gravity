const std = @import("std");
const ray = @import("raylib.zig");

const ArrayList = std.ArrayList;
const Vector2 = ray.struct_Vector2;
const Rectangle = ray.struct_Rectangle;

const WIDTH: f32 = 800;
const HEIGHT: f32 = 600;

const TIME_PER_UPDATE: f32 = @as(f32, 1.0 / 60.0);

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

    fn draw(self: *const @This()) void {
        ray.DrawRectangleRec(self.rectangle, self.color);

        ray.DrawCircleV(.{ .x = 300, .y = 50 }, self.charge, self.color);
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
    position: Vector2,
    size: f32,
    velocity: Vector2,
    player: *Player,

    const MIN_SIZE: f32 = 1.0;
    const MAX_SIZE: f32 = 20.0;

    const MIN_VELOCITY: f32 = 2.0;
    const MAX_VELOCITY: f32 = 7.0;

    fn init(player: *Player) Projectile {
        std.debug.print("{d}\n", .{player.charge});
        return .{
            .position = ray.Vector2Add(.{ .x = player.rectangle.x, .y = player.rectangle.y }, .{ .y = PADDLE_HEIGHT / 2, .x = PADDLE_WIDTH }),
            .size = player.charge,
            .velocity = ray.Vector2Scale(player.direction, calculateVelocity(player.charge)),
            .player = player,
        };
    }

    fn calculateVelocity(size: f32) f32 {
        const rate = (size - MIN_SIZE) / (MAX_SIZE - MIN_SIZE);
        return MAX_VELOCITY - rate * (MAX_VELOCITY - MIN_VELOCITY);
    }

    fn draw(self: *const @This()) void {
        ray.DrawCircleV(self.position, self.size, self.player.color);
    }

    fn update(self: *@This()) void {
        self.position = ray.Vector2Add(self.position, self.velocity);
    }

    fn checkCollision(self: *@This(), player: *Player) void {
        if (player != self.player and ray.CheckCollisionCircleRec(self.position, self.size, player.rectangle)) {
            self.velocity.x *= -1;
            self.player = player;
        }
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

        // update
        if (time_since_last_update > TIME_PER_UPDATE) {
            time_since_last_update = 0;

            if (ray.IsKeyDown(ray.KEY_DOWN)) {
                player1.move(.{ .y = 1 * PLAYER_SPEED });
            } else if (ray.IsKeyDown(ray.KEY_UP)) {
                player1.move(.{ .y = -1 * PLAYER_SPEED });
            }

            if (ray.IsKeyDown(ray.KEY_F)) {
                try player1.shoot(&projectiles);
            }

            for (projectiles.items) |*projectile| {
                projectile.update();
                projectile.checkCollision(&player1);
                projectile.checkCollision(&player2);
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
