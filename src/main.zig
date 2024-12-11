const std = @import("std");
const ray = @import("raylib.zig");

pub fn main() !void {
    const width = 800;
    const height = 600;

    ray.InitWindow(width, height, "gravity");
    defer ray.CloseWindow();

    while (!ray.WindowShouldClose()) {
        // update
        {}

        // drawing
        {
            ray.BeginDrawing();
            defer ray.EndDrawing();

            ray.ClearBackground(ray.WHITE);
            ray.DrawFPS(10, 10);
        }
    }
}

test "simple test" {}
