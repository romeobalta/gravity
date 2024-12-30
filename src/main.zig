const std = @import("std");
const ray = @import("raylib.zig");
const Particle = @import("particle.zig").Particle;
const Player = @import("player.zig").Player;
const Projectile = @import("projectile.zig").Projectile;
const Socket = @import("socket.zig").Socket;
const Package = @import("socket.zig").Package;
const ProjectileState = @import("socket.zig").ProjectileState;
const BoardState = @import("socket.zig").BoardState;
const CommandState = @import("socket.zig").CommandState;

const ArrayList = std.ArrayList;
const Vector2 = ray.Vector2;
const Color = ray.Color;
const Rectangle = ray.Rectangle;

pub const WIDTH: f32 = 1000;
pub const HEIGHT: f32 = 600;

pub const UPDATES_PER_SECOND: f32 = 60;
pub const TIME_PER_UPDATE: f32 = 1.0 / UPDATES_PER_SECOND;

pub const G = 9.8;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

var projectiles: ArrayList(Projectile) = undefined;
var particles: ArrayList(Particle) = undefined;

var player1: Player = undefined;
var player2: Player = undefined;

const ScoreBitField = packed struct {
    draw: bool = false,
    player1: bool = false,
    player2: bool = false,

    const Self = @This();

    fn reset(self: *Self) void {
        self.draw = false;
        self.player1 = false;
        self.player2 = false;
    }
};

var score = ScoreBitField{};

const GameState = enum {
    Menu,
    SinglePlayerLoop,
    ServerLogic,
    ClientLogic,
    Score,
};

// TODO: .Menu
var game_state: GameState = .Menu;
var countdown: f32 = 3.5;

var socket: Socket = undefined;

fn reset_game_state() void {
    particles.clearRetainingCapacity();
    projectiles.clearRetainingCapacity();

    player1 = Player.init_player_1();
    player2 = Player.init_player_2();
}

pub fn main() !void {
    ray.SetConfigFlags(ray.FLAG_MSAA_4X_HINT);
    ray.InitWindow(WIDTH, HEIGHT, "gravity");
    defer ray.CloseWindow();

    projectiles = ArrayList(Projectile).init(allocator);
    defer projectiles.deinit();

    particles = ArrayList(Particle).init(allocator);
    defer particles.deinit();

    ray.SetTargetFPS(60);

    reset_game_state();

    while (!ray.WindowShouldClose()) {
        if (countdown > 0) {
            countdown -= ray.GetFrameTime();
        }

        // update
        {
            switch (game_state) {
                .Menu => {
                    try menu_update();
                },
                .SinglePlayerLoop => {
                    try handle_player_input(&player1, true);
                    try update_objects();
                    handle_end_game();
                },
                .ServerLogic => {
                    try server_logic_loop();
                },
                .ClientLogic => {
                    try client_logic_loop();
                },
                .Score => {
                    score_loop();
                },
                // else => {
                //     std.debug.panic("oh no", .{});
                // },
            }
        }

        // drawing
        {
            ray.BeginDrawing();
            defer ray.EndDrawing();

            ray.ClearBackground(ray.BLACK);

            try main_draw();
            switch (game_state) {
                .Menu => {
                    try menu_draw();
                },
                .ServerLogic,
                .ClientLogic,
                => {
                    try network_draw();
                },
                .Score => {
                    try score_draw();
                },
                else => {},
            }
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
                game_state = .SinglePlayerLoop;
            },
            1 => {
                game_state = .ServerLogic;
                try server_logic_enter();
            },
            2 => {
                game_state = .ClientLogic;
                try client_logic_enter();
            },
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

var projectile_id: u32 = 0;
var client_projectile_id: u32 = 0;
var queue_shoot: ?CommandState = null;
fn handle_player_input(player: *Player, is_host: bool) !void {
    queue_shoot = null;
    if (ray.IsKeyDown(ray.KEY_DOWN)) {
        player.move(.{ .y = 1 });
    } else if (ray.IsKeyDown(ray.KEY_UP)) {
        player.move(.{ .y = -1 });
    }

    if (ray.IsKeyDown(ray.KEY_F)) {
        if (is_host) {
            if (player.can_shoot()) {
                try projectiles.append(Projectile.init(allocator, player, projectile_id));
                player.reset_shoot();
                projectile_id += 1;
            }
        } else {
            if (player.can_shoot()) {
                var new_projectile = Projectile.init(allocator, player, projectile_id);
                player.reset_shoot();
                queue_shoot = .{
                    .shoot = 1,
                    .position_x = new_projectile.position.x,
                    .position_y = new_projectile.position.y,
                    .velocity_x = new_projectile.velocity.x,
                    .velocity_y = new_projectile.velocity.y,
                    .charge = new_projectile.radius,
                };
                new_projectile.deinit();
                projectile_id += 1;
            }
        }
    }
}

fn update_objects() !void {
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

fn handle_end_game() void {
    score.reset();
    if (player1.life > 0 and player2.life <= 0) {
        game_state = .Score;
        score.player1 = true;
    } else if (player1.life <= 0 and player2.life > 0) {
        game_state = .Score;
        score.player2 = true;
    } else if (player1.life <= 0 and player2.life <= 0) {
        game_state = .Score;
        score.draw = true;
    }
}

fn score_draw() !void {
    {
        const font_size: c_int = 40;
        var string: []u8 = undefined;
        if (score.draw) {
            string = try std.fmt.allocPrintZ(allocator, "You're both losers lol", .{});
        } else if (score.player1) {
            string = try std.fmt.allocPrintZ(allocator, "Blue dude destroyed the orange one ggs", .{});
        } else if (score.player2) {
            string = try std.fmt.allocPrintZ(allocator, "Orange dude destroyed the blue one ggs", .{});
        } else {
            string = try std.fmt.allocPrintZ(allocator, "Something went terrribly wrong", .{});
        }
        defer allocator.free(string);
        const string_width = @divExact(ray.MeasureText(string.ptr, font_size), 2);
        const position_x: c_int = @as(c_int, WIDTH / 2) - (string_width);
        ray.DrawRectangleGradientH(position_x - 30, 90, 2 * string_width + 60, font_size + 15, ray.BLUE, ray.ORANGE);
        ray.DrawText(string.ptr, position_x, 100, font_size, ray.BLACK);
    }
    {
        const string = "Press ENTER to go back to main menu";
        const starting_pos = 200;
        const font_size: c_int = 30;
        const string_width = @divTrunc(ray.MeasureText(string.ptr, font_size), 2);
        const position_x: c_int = @as(c_int, WIDTH / 2) - (string_width);

        ray.DrawText(
            string.ptr,
            position_x,
            starting_pos,
            font_size,
            ray.BLUE,
        );
    }
}

fn score_loop() void {
    if (ray.IsKeyPressed(ray.KEY_ENTER)) {
        game_state = .Menu;
        reset_game_state();
    }
}

fn main_draw() !void {
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

fn network_draw() !void {
    const remaining = if (countdown_started) (3 - @floor(ray.GetTime() - game_started_time)) else 0;
    if (remaining >= 0) {
        {
            const font_size: c_int = 60;
            const string = "GAME STARTING";
            const string_width = @divExact(ray.MeasureText(string, font_size), 2);
            const position_x: c_int = @as(c_int, WIDTH / 2) - (string_width);
            ray.DrawRectangleGradientH(position_x - 30, 90, 2 * string_width + 60, font_size + 15, ray.BLUE, ray.ORANGE);
            ray.DrawText(string, position_x, 100, font_size, ray.BLACK);
        }
        {
            const string = if (countdown_started) try std.fmt.allocPrintZ(allocator, "{d}", .{remaining}) else try std.fmt.allocPrintZ(allocator, "Waiting for player to connect", .{});
            defer allocator.free(string);
            const starting_pos = 200;
            const font_size: c_int = 30;
            const string_width = @divTrunc(ray.MeasureText(string.ptr, font_size), 2);
            const position_x: c_int = @as(c_int, WIDTH / 2) - (string_width);

            ray.DrawText(
                string.ptr,
                position_x,
                starting_pos,
                font_size,
                ray.BLUE,
            );
        }
    } else if (!game_started) {
        game_started = true;
    }
}

fn update_remote_player(player: *Player, package: *const Package) !void {
    player.rectangle.x = package.player_state.position_x;
    player.rectangle.y = package.player_state.position_y;
    player.charge = package.player_state.charge;

    if (package.command.shoot == 1) {
        try projectiles.append(Projectile.init_remote(
            allocator,
            player,
            .{
                .x = package.command.position_x,
                .y = package.command.position_y,
                .z = package.command.velocity_x,
                .w = package.command.velocity_y,
            },
            package.command.charge,
            client_projectile_id,
        ));
        client_projectile_id += 1;
    }
}

fn server_logic_enter() !void {
    countdown_started = false;
    game_started = false;

    socket = try Socket.init("127.0.0.1", 42069);
}

var countdown_started = false;
var game_started = false;
var game_started_time: f64 = undefined;
fn start_countdown() void {
    countdown_started = true;
    game_started_time = ray.GetTime();
}

fn server_logic_loop() !void {
    var incoming_package: ?Package = null;

    if (socket.is_open) {
        const data = socket.receive();
        if (data) |package| {
            if (!countdown_started and package.packet_id == 0) {
                start_countdown();

                // respond to connection package
                try send_info(&player1, true);
            }

            std.debug.print("Received {any}\n", .{package});

            incoming_package = package;

            std.debug.print("Package {any}\n", .{package});
        }
    } else {
        socket.deinit();
        std.debug.print("NET: Socket is closed, going back to lobby \n", .{});
        game_state = .Menu;
        reset_game_state();
    }

    if (game_started) {
        if (incoming_package) |*package| {
            try update_remote_player(&player2, package);
        }
        try handle_player_input(&player1, true);
        try update_objects();
        try send_info(&player1, true);
        handle_end_game();
    }
}

fn client_logic_enter() !void {
    countdown_started = false;
    game_started = false;

    socket = try Socket.connect("127.0.0.1", 42069);

    // send connection package
    try send_info(&player2, false);
}

var package_id: u32 = 0;
fn client_logic_loop() !void {
    var incoming_package: ?Package = null;

    if (socket.is_open) {
        const data = socket.receive();
        if (data) |package| {
            if (!countdown_started and package.packet_id == 0) {
                start_countdown();
            }
            std.debug.print("{d} Received {any}\n", .{ package_id, package });

            incoming_package = package;
        }
    } else {
        socket.deinit();
        std.debug.print("NET: Socket is closed, going back to lobby \n", .{});
        game_state = .Menu;
        reset_game_state();
    }

    if (game_started) {
        if (incoming_package) |*package| {
            try update_remote_player(&player1, package);
            try handle_remote_objects(package);
        }
        try handle_player_input(&player2, false);
        try update_objects();
        try send_info(&player2, false);
        handle_end_game();
    }
}

fn handle_remote_objects(package: *Package) !void {
    for (0..package.board_state.projectile_count) |index| {
        var existing = false;
        const remote_projectile = &package.board_state.projectiles[index];
        for (projectiles.items) |*projectile| {
            if (projectile.id == remote_projectile.id) {
                existing = true;
                // projectile.to_delete = false;
                projectile.position.x = remote_projectile.position_x;
                projectile.position.y = remote_projectile.position_y;
                projectile.velocity.x = remote_projectile.velocity_x;
                projectile.velocity.y = remote_projectile.velocity_y;
            }
        }

        if (!existing) {
            try projectiles.append(Projectile.init_remote(
                allocator,
                if (remote_projectile.owner == 0) &player1 else &player2,
                .{
                    .x = remote_projectile.position_x,
                    .y = remote_projectile.position_y,
                    .z = remote_projectile.velocity_x,
                    .w = remote_projectile.velocity_y,
                },
                remote_projectile.charge,
                remote_projectile.id,
            ));
        }
    }
}

fn build_package(player: *const Player, is_server: bool) Package {
    var package = Package{
        .packet_id = package_id,
        .command = .{},
        .player_state = .{
            .position_x = player.rectangle.x,
            .position_y = player.rectangle.y,
            .charge = player.charge,
        },
        .board_state = std.mem.zeroes(BoardState),
    };

    if (queue_shoot) |command| {
        package.command = command;
    }

    if (is_server and projectiles.items.len > 0) {
        package.board_state.projectile_count = @intCast(projectiles.items.len);
        for (projectiles.items, 0..) |*projectile, index| {
            package.board_state.projectiles[index] = .{
                .id = projectile.id,
                .owner = if (projectile.player.side == .Left) 0 else 1,
                .position_x = projectile.position.x,
                .position_y = projectile.position.y,
                .velocity_x = projectile.velocity.x,
                .velocity_y = projectile.velocity.y,
                .charge = projectile.radius,
            };
        }
    }

    return package;
}

fn send_info(player: *const Player, from_server: bool) !void {
    const outgoing_package = build_package(player, from_server);
    package_id += 1;
    try socket.send(outgoing_package);
}

test "simple test" {
    var package = Package{
        .packet_id = 1,
        .player_state = .{
            .position_x = 10,
            .position_y = 10,
            .charge = 5,
        },
        .board_state = BoardState.init(0),
    };

    package.board_state.projectiles[49] = .{
        .position_x = 1,
        .position_y = 1,
        .velocity_x = 10,
        .velocity_y = 10,
    };

    const encoded_package = package.encode();

    var decoded_package = Package{};
    decoded_package.decode(encoded_package[0..]);

    std.debug.assert(decoded_package.packet_id == package.packet_id);
    std.debug.assert(decoded_package.player_state.position_x == package.player_state.position_x);
    std.debug.assert(decoded_package.player_state.position_y == package.player_state.position_y);
    std.debug.assert(decoded_package.board_state.projectile_count == package.board_state.projectile_count);
    std.debug.assert(decoded_package.board_state.projectiles[49].position_x == package.board_state.projectiles[49].position_x);
    std.debug.assert(decoded_package.board_state.projectiles[49].position_y == package.board_state.projectiles[49].position_y);
    std.debug.assert(decoded_package.board_state.projectiles[49].velocity_x == package.board_state.projectiles[49].velocity_x);
    std.debug.assert(decoded_package.board_state.projectiles[49].velocity_y == package.board_state.projectiles[49].velocity_y);
}
