const std = @import("std");
const ray = @import("raylib.zig");
const Particle = @import("particle.zig").Particle;
const Player = @import("player.zig").Player;
const Projectile = @import("projectile.zig").Projectile;
const Socket = @import("socket.zig").Socket;
const ClientPackage = @import("socket.zig").ClientPackage;
const ProjectileState = @import("socket.zig").ProjectileState;
const BoardState = @import("socket.zig").BoardState;

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
    Menu,
    Loop,
    ServerWait,
    ClientLoop,
};

// TODO: .Menu
var game_state: GameState = .Menu;
var countdown: f32 = 3.5;

var socket: Socket = undefined;

pub fn main() !void {
    ray.SetConfigFlags(ray.FLAG_MSAA_4X_HINT);
    ray.InitWindow(WIDTH, HEIGHT, "gravity");
    defer ray.CloseWindow();

    // var time_since_last_update: f32 = 0;

    projectiles = ArrayList(Projectile).init(allocator);
    defer projectiles.deinit();

    particles = ArrayList(Particle).init(allocator);
    defer particles.deinit();

    ray.SetTargetFPS(60);

    while (!ray.WindowShouldClose()) {
        // time_since_last_update += ray.GetFrameTime();

        if (countdown > 0) {
            countdown -= ray.GetFrameTime();
        }

        // update
        // if (time_since_last_update > TIME_PER_UPDATE)
        {
            // time_since_last_update = 0;

            switch (game_state) {
                .Menu => {
                    try menu_update();
                },
                .Loop => {
                    try loop_update();
                },
                .ServerWait => {
                    try server_wait_loop();
                },
                else => {
                    std.debug.panic("oh no", .{});
                },
            }
        }

        // drawing
        {
            ray.BeginDrawing();
            defer ray.EndDrawing();

            ray.ClearBackground(ray.BLACK);
            // ray.DrawFPS(10, HEIGHT - 20);

            if (game_state == .Menu) {
                try menu_draw();
            }
            try loop_draw();
        }
    }
}

fn menu_update() !void {
    if (ray.IsKeyPressed(ray.KEY_DOWN)) {
        selected = if (selected + 1 >= options.len) 0 else selected + 1;
    } else if (ray.IsKeyPressed(ray.KEY_UP)) {
        selected = if (selected - 1 < 0) options.len - 1 else selected - 1;
    }

    if (ray.IsKeyPressed(ray.KEY_ENTER)) {
        switch (selected) {
            0 => {
                game_state = .Loop;
            },
            1 => {
                try server_wait_enter();

                game_state = .ServerWait;
            },
            2 => {},
            else => {},
        }
    }
}

const options = [_][]const u8{ "Start local game", "Host game", "Connect to remote game" };
var selected: c_int = 0;
var menu_counter: f32 = 0;
fn menu_draw() !void {
    {
        const font_size: c_int = 60;
        const string = "GRAVITY";
        const string_width = @divExact(ray.MeasureText(string, font_size), 2);
        const position_x: c_int = @as(c_int, WIDTH / 2) - (string_width);
        ray.DrawRectangleGradientH(position_x - 30, 90, 2 * string_width + 60, font_size + 15, ray.BLUE, ray.ORANGE);
        ray.DrawText(string, position_x, 100, font_size, ray.BLACK);
    }

    {
        const starting_pos = 200;
        const font_size: c_int = 30;
        for (options, 0..) |option, i| {
            const string_width = @divTrunc(ray.MeasureText(option.ptr, font_size), 2);
            const position_x: c_int = @as(c_int, WIDTH / 2) - (string_width);
            if (i == selected) {
                menu_counter += ray.GetFrameTime();
                const opacity = 0.25 * @sin(((menu_counter * std.math.pi) + 4.7) / 0.7) + 0.75;
                ray.DrawText(
                    option.ptr,
                    position_x,
                    starting_pos + (@as(c_int, @intCast(i)) * 40),
                    font_size,
                    ray.ColorAlpha(ray.ORANGE, opacity),
                );
            } else {
                ray.DrawText(
                    option.ptr,
                    position_x,
                    starting_pos + (@as(c_int, @intCast(i)) * 40),
                    font_size,
                    ray.BLUE,
                );
            }
        }
    }
}

fn loop_update() !void {
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
                if (projectile.radius + projectile.extra_mass == target.radius + target.extra_mass) {
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
                } else if (projectile.radius + projectile.extra_mass > target.radius + target.extra_mass) {
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

fn loop_draw() !void {
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

fn server_wait_enter() !void {
    socket = try Socket.init("127.0.0.1", 42069);
}

fn server_wait_loop() !void {
    if (socket.is_open) {
        socket.receive();
    } else {
        socket.deinit();
        std.debug.print("NET: Socket is closed, going back to lobby \n", .{});
        game_state = .Menu;
    }
}

test "simple test" {
    var client_package = ClientPackage{
        .packet_id = 1,
        .player_state = .{
            .position_x = 10,
            .position_y = 10,
            .charge = 5,
        },
        .board_state = BoardState.init(50),
    };

    client_package.board_state.projectiles[49] = .{
        .position_x = 1,
        .position_y = 1,
        .velocity_x = 10,
        .velocity_y = 10,
    };

    const encoded_package = client_package.encode();

    var decoded_package = ClientPackage{};
    decoded_package.decode(encoded_package[0..]);

    std.debug.assert(decoded_package.packet_id == client_package.packet_id);
    std.debug.assert(decoded_package.player_state.position_x == client_package.player_state.position_x);
    std.debug.assert(decoded_package.player_state.position_y == client_package.player_state.position_y);
    std.debug.assert(decoded_package.board_state.projectile_count == client_package.board_state.projectile_count);
    std.debug.assert(decoded_package.board_state.projectiles[49].position_x == client_package.board_state.projectiles[49].position_x);
    std.debug.assert(decoded_package.board_state.projectiles[49].position_y == client_package.board_state.projectiles[49].position_y);
    std.debug.assert(decoded_package.board_state.projectiles[49].velocity_x == client_package.board_state.projectiles[49].velocity_x);
    std.debug.assert(decoded_package.board_state.projectiles[49].velocity_y == client_package.board_state.projectiles[49].velocity_y);
}
