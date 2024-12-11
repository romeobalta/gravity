const std = @import("std");
const ray = @import("raylib.zig");

const ArrayList = std.ArrayList;
const Vector2 = ray.struct_Vector2;

const TIME_PER_UPDATE: f32 = @as(f32, 1.0 / 60.0);

const PADDLE_WIDTH: u32 = 10;
const PADDLE_HEIGHT: u32 = 60;

const PLAYER_SPEED: f32 = 5.0;
const PLAYER_COOLDOWN: f32 = 1.0;

const STARTING_VELOCITY: Vector2 = .{ .x = 5.0, .y = 0.0 };

const Player = struct {
    position: Vector2,
    color: ray.struct_Color,
    charge: f32 = 0.0,
    cooldown: f32 = PLAYER_COOLDOWN,

    fn init() Player {
        return .{
            .position = .{
                .x = 5.0,
                .y = 0.0,
            },
            .color = ray.BLUE,
        };
    }

    fn draw(self: *const @This()) void {
        ray.DrawRectangleV(self.position, .{ .x = PADDLE_WIDTH, .y = PADDLE_HEIGHT }, self.color);

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
        self.position = ray.Vector2Add(self.position, velocity);
    }

    fn shoot(self: *@This(), projectiles: *ArrayList(Projectile)) !void {
        if (self.charge >= Projectile.STARTING_SIZE) {
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

    const STARTING_SIZE: f32 = 1;
    const MAX_SIZE: f32 = 20.0;

    fn init(player: *Player) Projectile {
        std.debug.print("{d}\n", .{player.charge});
        return .{
            .position = ray.Vector2Add(player.position, .{ .y = PADDLE_HEIGHT / 2, .x = PADDLE_WIDTH }),
            .size = player.charge,
            .velocity = STARTING_VELOCITY,
            .player = player,
        };
    }

    fn draw(self: *const @This()) void {
        ray.DrawCircleV(self.position, self.size, self.player.color);
    }

    fn update(self: *@This()) void {
        self.position = ray.Vector2Add(self.position, self.velocity);
    }
};

pub fn main() !void {
    const width = 800;
    const height = 600;

    ray.InitWindow(width, height, "gravity");
    defer ray.CloseWindow();

    var time_since_last_update: f32 = 0;

    var player = Player.init();

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
                player.move(.{ .y = 1 * PLAYER_SPEED });
            } else if (ray.IsKeyDown(ray.KEY_UP)) {
                player.move(.{ .y = -1 * PLAYER_SPEED });
            }

            if (ray.IsKeyDown(ray.KEY_F)) {
                try player.shoot(&projectiles);
            }

            for (projectiles.items) |*projectile| {
                projectile.update();
            }
            player.update();
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
            player.draw();
        }
    }
}

test "simple test" {}
