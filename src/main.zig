const std = @import("std");
const ray = @import("raylib.zig");

const ArrayList = std.ArrayList;
const Vector2 = ray.struct_Vector2;
const Color = ray.struct_Color;
const Rectangle = ray.struct_Rectangle;

const WIDTH: f32 = 800;
const HEIGHT: f32 = 600;

const UPDATES_PER_SECOND: f32 = 60;
const TIME_PER_UPDATE: f32 = 1.0 / UPDATES_PER_SECOND;

const G = 9.8;

const PADDLE_WIDTH: f32 = 10;
const PADDLE_HEIGHT: f32 = 60;

const PLAYER_SPEED: f32 = 10;
const PLAYER_COOLDOWN: f32 = 0.5;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

var projectiles: ArrayList(Projectile) = undefined;
var particles: ArrayList(Particle) = undefined;

var player1 = Player.init_player_1();
var player2 = Player.init_player_2();

const Side = enum {
    Left,
    Right,
};

const GameState = enum {
    Start,
    Loop,
};

// TODO: .Start
var game_state: GameState = .Loop;
var countdown: f32 = 3.5;

const Player = struct {
    rectangle: Rectangle,
    color: ray.Color,
    charge: f32 = 0.0,
    cooldown: f32 = PLAYER_COOLDOWN,
    direction: Vector2 = .{ .x = 1, .y = 0 },
    life: f32 = 100,
    side: Side,

    fn init_player_1() Player {
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

    fn init_player_2() Player {
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
        ray.DrawRectangleLinesEx(self.rectangle, 1, self.color);

        const charge_height = ray.Remap(self.charge, Projectile.MIN_SIZE, Projectile.MAX_SIZE, 0, self.rectangle.height);
        const charge_rect: ray.struct_Rectangle = .{
            .x = self.rectangle.x,
            .y = self.rectangle.y + (self.rectangle.height - charge_height) / 2,
            .width = self.rectangle.width,
            .height = charge_height,
        };
        ray.DrawRectangleRec(charge_rect, self.color);

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
    tail: ArrayList(Particle),

    const MIN_SIZE: f32 = 5.0;
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
            .velocity = ray.Vector2Scale(player.direction, calculate_velocity(player.charge)),
            .player = player,
            .tail = ArrayList(Particle).init(allocator),
        };
    }

    fn deinit(self: *@This()) void {
        self.tail.clearAndFree();
        self.tail.deinit();
    }

    fn calculate_velocity(size: f32) f32 {
        return ray.Remap(size, MIN_SIZE, MAX_SIZE, MAX_VELOCITY, MIN_VELOCITY);
    }

    fn draw(self: *const @This()) void {
        for (self.tail.items) |particle| {
            particle.draw();
        }

        ray.DrawCircleV(self.position, self.radius, self.player.color);
    }

    fn update(self: *@This()) void {
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

    fn check_projectile_collision(self: *@This(), target: *@This()) bool {
        const distance = ray.Vector2Distance(self.position, target.position);
        return distance <= (self.radius + target.radius);
    }

    fn check_player_collision(self: *@This(), player: *Player) void {
        if (ray.CheckCollisionCircleRec(self.position, self.radius, player.rectangle)) {
            self.velocity.x *= -1;
            self.player = player;
        }
    }

    fn check_out_of_bounds(self: *@This()) bool {
        if (self.position.y - self.radius <= 0 or self.position.y + self.radius >= HEIGHT) {
            self.velocity.y *= -1;
        }

        if (self.position.x - self.radius <= 0 or self.position.x + self.radius >= WIDTH) {
            return true;
        }

        return false;
    }

    fn compute_gravity(self: *@This(), target: *@This()) void {
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
        const impact = ray.Remap(size_diff, min_size_diff, max_size_diff, max_impact, min_impact);

        self.forces = ray.Vector2Add(self.forces, ray.Vector2Scale(target.velocity, impact * impact));

        if (self.radius < MAX_SIZE) {
            self.radius += target.radius;
        }
    }
};

fn component_blend(component: u8, blend: u8, amount: u8) u8 {
    return @intCast((@as(u16, component) * @as(u16, amount) + @as(u16, blend) * (255 - @as(u16, amount))) / 255);
}

fn color_blend(color: ray.Color, blend: ray.Color, amount: u8) ray.Color {
    return .{
        .r = component_blend(color.r, blend.r, amount),
        .g = component_blend(color.g, blend.g, amount),
        .b = component_blend(color.b, blend.b, amount),
        .a = color.a,
    };
}

const Particle = struct {
    position: Vector2,
    size: f32,
    velocity: Vector2 = ray.Vector2Zero(),
    decay_speed: f32 = 0.1,
    color: ray.Color = ray.WHITE,
    projectile: ?*Projectile = null,

    const MIN_SIZE: f32 = 2;
    const MAX_SIZE: f32 = 5;

    fn init_debris(position: Vector2, velocity_x: f32, color: ray.Color) @This() {
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

    fn init_trail(projectile: *Projectile) @This() {
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

    fn update(self: *@This()) void {
        self.position = ray.Vector2Add(self.position, self.velocity);
        self.size -= self.decay_speed;
    }

    fn draw(self: *const @This()) void {
        ray.DrawCircleV(
            self.position,
            self.size,
            self.color,
        );
    }
};

pub fn main() !void {
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
        const string_width = @divExact(ray.MeasureText(string, font_size), 2);
        const position_x: c_int = @as(c_int, WIDTH / 2) - (string_width);
        ray.DrawText(string, position_x, 150, font_size, ray.WHITE);
    }
}

fn update_loop() !void {
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

            if (projectile.check_projectile_collision(target)) {
                if (projectile.radius == target.radius) {
                    projectile.to_delete = true;
                    target.to_delete = true;

                    try create_debris(projectile);
                    try create_debris(target);
                }
                if (projectile.radius > target.radius) {
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

    try player1.draw();
    try player2.draw();
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
