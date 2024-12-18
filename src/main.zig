const std = @import("std");
const ray = @import("raylib.zig");
const Particle = @import("particle.zig").Particle;
const Player = @import("player.zig").Player;
const Projectile = @import("projectile.zig").Projectile;

const ArrayList = std.ArrayList;
const Vector2 = ray.Vector2;
const Color = ray.Color;
const Rectangle = ray.Rectangle;

pub const WIDTH: f32 = 1600;
pub const HEIGHT: f32 = 800;

pub const UPDATES_PER_SECOND: f32 = 60;
pub const TIME_PER_UPDATE: f32 = 1.0 / UPDATES_PER_SECOND;

pub const G = 9.8;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

var projectiles: ArrayList(Projectile) = undefined;
var particles: ArrayList(Particle) = undefined;

var player1 = Player.init_player_1();
var player2 = Player.init_player_2();

const GameState = enum {
    Start,
    Loop,
};

// TODO: .Start
var game_state: GameState = .Loop;
var countdown: f32 = 3.5;

pub fn main() !void {
    ray.SetConfigFlags(ray.FLAG_MSAA_4X_HINT);
    ray.InitWindow(WIDTH, HEIGHT, "gravity");
    defer ray.CloseWindow();

    var time_since_last_update: f32 = 0;

    projectiles = ArrayList(Projectile).init(allocator);
    defer projectiles.deinit();

    particles = ArrayList(Particle).init(allocator);
    defer particles.deinit();

    while (!ray.WindowShouldClose()) {
        time_since_last_update += ray.GetFrameTime();

        if (countdown > 0) {
            countdown -= ray.GetFrameTime();
        }

        // update
        if (time_since_last_update > TIME_PER_UPDATE) {
            time_since_last_update = 0;

            switch (game_state) {
                .Start => {
                    try update_start();
                },
                .Loop => {
                    try update_loop();
                },
            }
        }

        // drawing
        {
            ray.BeginDrawing();
            defer ray.EndDrawing();

            ray.ClearBackground(ray.BLACK);
            // ray.DrawFPS(10, HEIGHT - 20);

            if (game_state == .Start) {
                try draw_start();
            }
            try draw_loop();
        }
    }
}

fn update_start() !void {
    if (countdown <= 0) {
        game_state = .Loop;
    }
}

fn draw_start() !void {
    const font_size: c_int = 60;

    {
        const string = "Game is starting";
        const string_width = @divExact(ray.MeasureText(string, font_size), 2);
        const position_x: c_int = @as(c_int, WIDTH / 2) - (string_width);
        ray.DrawText(string, position_x, 100, font_size, ray.WHITE);
    }

    {
        const remaining = @floor(countdown);
        const string = try std.fmt.allocPrintZ(allocator, "{d}", .{remaining});
        defer allocator.free(string);

        const string_width = @divExact(ray.MeasureText(string, font_size), 2);
        const position_x: c_int = @as(c_int, WIDTH / 2) - (string_width);
        ray.DrawText(string, position_x, 150, font_size, ray.WHITE);
    }
}

fn update_loop() !void {
    if (ray.IsKeyDown(ray.KEY_DOWN)) {
        player1.move(.{ .y = 1 });
    } else if (ray.IsKeyDown(ray.KEY_UP)) {
        player1.move(.{ .y = -1 });
    }

    if (ray.IsKeyDown(ray.KEY_F)) {
        try player1.shoot(allocator, &projectiles);
    }

    for (projectiles.items, 0..) |*projectile, i| {
        for (projectiles.items, 0..) |*target, j| {
            if (i >= j) continue;

            if (projectile.check_projectile_collision(target)) {
                if (projectile.radius == target.radius) {
                    const p_velocity_magnitude = ray.Vector2Length(projectile.velocity);
                    const t_velocity_magnitude = ray.Vector2Length(target.velocity);
                    if (p_velocity_magnitude > t_velocity_magnitude) {
                        target.to_delete = true;
                        try create_debris(target);
                        projectile.consume(target);
                    } else {
                        projectile.to_delete = true;
                        try create_debris(projectile);
                        target.consume(projectile);
                    }
                } else if (projectile.radius > target.radius) {
                    target.to_delete = true;
                    try create_debris(target);
                    projectile.consume(target);
                } else {
                    projectile.to_delete = true;
                    try create_debris(projectile);
                    target.consume(projectile);
                }
                continue;
            }

            projectile.compute_gravity(target);
        }

        if (projectile.check_out_of_bounds()) {
            projectile.to_delete = true;

            if (projectile.position.x <= WIDTH / 2) {
                player1.life -= @ceil(projectile.radius);
            } else {
                player2.life -= @ceil(projectile.radius);
            }

            try create_debris(projectile);

            continue;
        }

        projectile.check_player_collision(&player1);
        projectile.check_player_collision(&player2);

        projectile.update();

        if (!projectile.to_delete) {
            try projectile.tail.append(Particle.init_trail(projectile));
        }
    }

    {
        var i = projectiles.items.len;
        while (i > 0) : (i -= 1) {
            const index = i - 1;
            const projectile = &projectiles.items[index];

            if (projectile.to_delete) {
                projectile.deinit();
                _ = projectiles.orderedRemove(index);
            }
        }
    }

    {
        var i = particles.items.len;
        while (i > 0) : (i -= 1) {
            const index = i - 1;
            var particle = &particles.items[index];

            particle.update();

            if (particle.size <= 0) {
                _ = particles.orderedRemove(index);
            }
        }
    }

    player1.update();
    player2.update();
}

fn draw_loop() !void {
    for (particles.items) |particle| {
        particle.draw();
    }

    for (projectiles.items) |projectile| {
        projectile.draw();
    }

    try player1.draw(allocator);
    try player2.draw(allocator);
}

fn create_debris(projectile: *Projectile) !void {
    const particle_count = std.Random.intRangeAtMost(std.crypto.random, usize, 5, 10);

    for (0..particle_count) |_| {
        try particles.append(Particle.init_debris(
            projectile.position,
            projectile.velocity.x,
            projectile.player.color,
        ));
    }
}

test "simple test" {}
