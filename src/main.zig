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

const PLAYER_SPEED: f32 = 10;
const PLAYER_COOLDOWN: f32 = 0.5;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

var projectiles: ArrayList(Projectile) = undefined;

var player1 = Player.player1();
var player2 = Player.player2();

const Side = enum {
    Left,
    Right,
};

const GameState = enum {
    Start,
    Loop,
};

var game_state: GameState = .Start;
var countdown: f32 = 3.5;

const Player = struct {
    rectangle: Rectangle,
    color: ray.struct_Color,
    charge: f32 = 0.0,
    cooldown: f32 = PLAYER_COOLDOWN,
    direction: Vector2 = .{ .x = 1, .y = 0 },
    life: f32 = 100,
    side: Side,

    fn player1() Player {
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

    fn player2() Player {
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

    fn draw(self: *const @This()) !void {
        ray.DrawRectangleRec(self.rectangle, self.color);

        // draw life
        {
            const font_size: c_int = 30;
            const string = try std.fmt.allocPrintZ(allocator, "Life {d}", .{self.life});
            const string_width = ray.MeasureText(string, font_size);
            const position_x: c_int = switch (self.side) {
                .Left => 10,
                .Right => @as(c_int, WIDTH) - string_width - 10,
            };
            ray.DrawText(string, position_x, 10, font_size, self.color);
        }
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
        var new_pos = ray.Vector2Add(.{ .x = self.rectangle.x, .y = self.rectangle.y }, velocity);

        if (new_pos.y <= 0) {
            new_pos.y = 0;
        } else if (new_pos.y + self.rectangle.height >= HEIGHT) {
            new_pos.y = HEIGHT - self.rectangle.height;
        }

        self.rectangle.x = new_pos.x;
        self.rectangle.y = new_pos.y;
    }

    fn shoot(self: *@This(), projectile_list: *ArrayList(Projectile)) !void {
        if (self.cooldown <= 0 and self.charge >= Projectile.MIN_SIZE) {
            try projectile_list.append(Projectile.init(self));
            self.charge = Projectile.MIN_SIZE;
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

    const MIN_SIZE: f32 = 3.0;
    const MAX_SIZE: f32 = 20.0;

    const MIN_VELOCITY: f32 = 1.0;
    const MAX_VELOCITY: f32 = 7.0;

    const MAX_DISTANCE_GRAVITY: f32 = 100;

    fn init(player: *Player) Projectile {
        const position_multiplier: f32 = switch (player.side) {
            .Left => 1,
            .Right => -1,
        };

        return .{
            .position = ray.Vector2Add(.{
                .x = player.rectangle.x,
                .y = player.rectangle.y,
            }, .{
                .y = PADDLE_HEIGHT / 2,
                .x = (PADDLE_WIDTH + player.charge + 10) * position_multiplier,
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
    }

    fn update(self: *@This()) void {
        self.velocity = ray.Vector2Add(self.velocity, self.forces);
        self.position = ray.Vector2Add(self.position, self.velocity);
        self.forces = ray.Vector2Zero();
    }

    fn checkProjectileCollision(self: *@This(), target: *@This()) bool {
        const distance = ray.Vector2Distance(self.position, target.position);
        return distance <= (self.radius + target.radius);
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
        const gravity = (G * self.radius * self.radius * target.radius * target.radius) / (distance * distance);

        const direction = ray.Vector2Normalize(ray.Vector2Subtract(self.position, target.position));

        self.forces = ray.Vector2Add(self.forces, ray.Vector2Negate(ray.Vector2Scale(direction, gravity / (self.radius * self.radius))));
        target.forces = ray.Vector2Add(target.forces, ray.Vector2Scale(direction, gravity / (target.radius * target.radius)));
    }

    fn consume(self: *@This(), target: *@This()) void {
        const size_diff = self.radius - target.radius;
        const min_size_diff = 0;
        const max_size_diff = MAX_SIZE - MIN_SIZE;

        const min_impact = 0.1;
        const max_impact = 0.99;

        const rate = (size_diff - min_size_diff) / (max_size_diff - min_size_diff);
        const impact = max_impact - rate * (max_impact - min_impact);

        self.forces = ray.Vector2Add(self.forces, ray.Vector2Scale(target.velocity, impact * impact));

        if (self.radius < MAX_SIZE) {
            self.radius += target.radius;
        }
    }
};

pub fn main() !void {
    ray.InitWindow(WIDTH, HEIGHT, "gravity");
    defer ray.CloseWindow();

    var time_since_last_update: f32 = 0;

    projectiles = ArrayList(Projectile).init(allocator);
    defer projectiles.deinit();

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
                    try updateStart();
                },
                .Loop => {
                    try updateLoop();
                },
            }
        }

        // drawing
        {
            ray.BeginDrawing();
            defer ray.EndDrawing();

            ray.ClearBackground(ray.BLACK);
            // ray.DrawFPS(10, 10);

            if (game_state == .Start) {
                try drawStart();
            }
            try drawLoop();
        }
    }
}

fn updateStart() !void {
    if (countdown <= 0) {
        game_state = .Loop;
    }
}

fn drawStart() !void {
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
        const string_width = @divExact(ray.MeasureText(string, font_size), 2);
        const position_x: c_int = @as(c_int, WIDTH / 2) - (string_width);
        ray.DrawText(string, position_x, 150, font_size, ray.WHITE);
    }
}

fn updateLoop() !void {
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
                    projectile.consume(target);
                } else {
                    projectile.to_delete = true;
                    target.consume(projectile);
                }
                continue;
            }

            projectile.computeGravity(target);
        }

        if (projectile.checkOutOfBounds()) {
            projectile.to_delete = true;

            if (projectile.position.x <= WIDTH / 2) {
                player1.life -= @ceil(projectile.radius);
            } else {
                player2.life -= @ceil(projectile.radius);
            }

            continue;
        }

        projectile.checkPlayerCollision(&player1);
        projectile.checkPlayerCollision(&player2);

        projectile.update();
    }

    var i = projectiles.items.len;
    while (i > 0) : (i -= 1) {
        if (projectiles.items[i - 1].to_delete) {
            _ = projectiles.orderedRemove(i - 1);
        }
    }

    player1.update();
    player2.update();
}

fn drawLoop() !void {
    for (projectiles.items) |projectile| {
        projectile.draw();
    }

    try player1.draw();
    try player2.draw();
}

test "simple test" {}
