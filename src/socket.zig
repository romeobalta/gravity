const std = @import("std");
const builtin = @import("builtin");
const ray = @import("raylib.zig");

const Vector2 = ray.Vector2;

pub const Socket = struct {
    local_address: std.net.Address = undefined,
    remote_address: std.net.Address = undefined,
    socket: std.posix.socket_t,
    is_open: bool = false,
    is_server: bool = false,

    const Self = @This();

    pub fn init(ip: []const u8, port: u16) !Self {
        const parsed_address = try std.net.Address.parseIp4(ip, port);
        const sock = try std.posix.socket(std.posix.AF.INET, std.posix.SOCK.DGRAM | std.posix.SOCK.NONBLOCK, 0);
        try std.posix.bind(sock, @ptrCast(&parsed_address), parsed_address.getOsSockLen());

        return .{
            .local_address = parsed_address,
            .socket = sock,
            .is_open = true,
            .is_server = true,
        };
    }

    pub fn connect(ip: []const u8, port: u16) !Self {
        const parsed_address = try std.net.Address.parseIp4(ip, port);
        const sock = try std.posix.socket(std.posix.AF.INET, std.posix.SOCK.DGRAM | std.posix.SOCK.NONBLOCK, 0);

        return .{
            .remote_address = parsed_address,
            .socket = sock,
            .is_open = true,
        };
    }

    pub fn deinit(self: *Self) void {
        if (comptime builtin.target.os.tag == .windows) {
            std.os.windows.closesocket(self.socket);
            return;
        }

        std.posix.close(self.socket);
        self.is_open = false;
    }

    pub fn send(self: *const Self, package: Package) !void {
        const data = package.encode();
        std.debug.print("Sending {any}\n", .{package});
        const sent = try std.posix.sendto(
            self.socket,
            data[0..],
            0,
            @ptrCast(&self.remote_address),
            self.remote_address.getOsSockLen(),
        );
        std.debug.print("Sent: {d}\n", .{sent});
    }

    pub fn receive(self: *Self) ?Package {
        var buffer: [2048]u8 = undefined;
        var from: std.net.Address = undefined;
        var from_length: u32 = @sizeOf(@TypeOf(from.in6));

        while (true) {
            const received = std.posix.recvfrom(self.socket, buffer[0..], 0, @ptrCast(&from), &from_length) catch 0;

            if (received <= 0) {
                break;
            }

            std.debug.print("NET: Received {d}\n", .{received});

            if (received == PACKAGE_SIZE) {
                std.mem.copyForwards(std.net.Address, (&self.remote_address)[0..1], (&from)[0..1]);
                var package = Package{};
                package.decode(buffer[0..]);
                return package;
            }
        }

        return null;
    }
};

const PACKAGE_SIZE =
    // packet id
    @sizeOf(u32) +
    // player state
    @sizeOf(PlayerState) +
    // command
    @sizeOf(CommandState) +
    // projectile count
    @sizeOf(u8) +
    // projectiles
    @sizeOf(ProjectileState) * MAX_PROJECTILES;

pub const Package = extern struct {
    packet_id: u32 = 0,
    player_state: PlayerState = .{},
    command: CommandState = .{},
    board_state: BoardState = .{},

    const Self = @This();

    pub fn init(packet_id: u32) Self {
        return .{
            .packet_id = packet_id,
        };
    }

    pub fn encode(self: *const Self) [PACKAGE_SIZE]u8 {
        var buffer: [PACKAGE_SIZE]u8 = std.mem.zeroes([PACKAGE_SIZE]u8);

        std.mem.writePackedInt(u32, buffer[0..], 0, @bitCast(self.packet_id), .little);
        self.player_state.encode(buffer[0..], @bitOffsetOf(Self, "player_state"));
        self.command.encode(buffer[0..], @bitOffsetOf(Self, "command"));
        self.board_state.encode(buffer[0..], @bitOffsetOf(Self, "board_state"));

        return buffer;
    }

    pub fn decode(self: *Self, data: []const u8) void {
        self.packet_id = std.mem.readPackedInt(u32, data[0..], 0, .little);
        self.player_state.decode(data, @bitOffsetOf(Self, "player_state"));
        self.command.decode(data, @bitOffsetOf(Self, "command"));
        self.board_state.decode(data, @bitOffsetOf(Self, "board_state"));
    }
};

const PlayerState = extern struct {
    position_x: f32 = 0.0,
    position_y: f32 = 0.0,
    charge: f32 = 0.0,

    const Self = @This();

    pub fn encode(self: *const Self, buffer: []u8, offset: usize) void {
        std.mem.writePackedInt(
            u32,
            buffer,
            offset + @bitOffsetOf(Self, "position_x"),
            @bitCast(self.position_x),
            .little,
        );
        std.mem.writePackedInt(
            u32,
            buffer,
            offset + @bitOffsetOf(Self, "position_y"),
            @bitCast(self.position_y),
            .little,
        );
        std.mem.writePackedInt(
            u32,
            buffer,
            offset + @bitOffsetOf(Self, "charge"),
            @bitCast(self.charge),
            .little,
        );
    }

    pub fn decode(self: *Self, buffer: []const u8, offset: usize) void {
        self.position_x = @bitCast(std.mem.readPackedInt(
            u32,
            buffer,
            offset + @bitOffsetOf(Self, "position_x"),
            .little,
        ));
        self.position_y = @bitCast(std.mem.readPackedInt(
            u32,
            buffer,
            offset + @bitOffsetOf(Self, "position_y"),
            .little,
        ));
        self.charge = @bitCast(std.mem.readPackedInt(
            u32,
            buffer,
            offset + @bitOffsetOf(Self, "charge"),
            .little,
        ));
    }
};

pub const CommandState = extern struct {
    shoot: u32 = 0,
    position_x: f32 = 0,
    position_y: f32 = 0,
    velocity_x: f32 = 0,
    velocity_y: f32 = 0,
    charge: f32 = 0,

    const Self = @This();

    pub fn encode(self: *const Self, buffer: []u8, offset: usize) void {
        std.mem.writePackedInt(
            u32,
            buffer,
            offset + @bitOffsetOf(Self, "shoot"),
            self.shoot,
            .little,
        );
        std.mem.writePackedInt(
            u32,
            buffer,
            offset + @bitOffsetOf(Self, "position_x"),
            @bitCast(self.position_x),
            .little,
        );
        std.mem.writePackedInt(
            u32,
            buffer,
            offset + @bitOffsetOf(Self, "position_y"),
            @bitCast(self.position_y),
            .little,
        );
        std.mem.writePackedInt(
            u32,
            buffer,
            offset + @bitOffsetOf(Self, "velocity_x"),
            @bitCast(self.velocity_x),
            .little,
        );
        std.mem.writePackedInt(
            u32,
            buffer,
            offset + @bitOffsetOf(Self, "velocity_y"),
            @bitCast(self.velocity_y),
            .little,
        );
        std.mem.writePackedInt(
            u32,
            buffer,
            offset + @bitOffsetOf(Self, "charge"),
            @bitCast(self.charge),
            .little,
        );
    }

    pub fn decode(self: *Self, buffer: []const u8, offset: usize) void {
        self.shoot = std.mem.readPackedInt(
            u32,
            buffer,
            offset + @bitOffsetOf(Self, "shoot"),
            .little,
        );
        self.position_x = @bitCast(std.mem.readPackedInt(
            u32,
            buffer,
            offset + @bitOffsetOf(Self, "position_x"),
            .little,
        ));
        self.position_y = @bitCast(std.mem.readPackedInt(
            u32,
            buffer,
            offset + @bitOffsetOf(Self, "position_y"),
            .little,
        ));
        self.velocity_x = @bitCast(std.mem.readPackedInt(
            u32,
            buffer,
            offset + @bitOffsetOf(Self, "velocity_x"),
            .little,
        ));
        self.velocity_y = @bitCast(std.mem.readPackedInt(
            u32,
            buffer,
            offset + @bitOffsetOf(Self, "velocity_y"),
            .little,
        ));
        self.charge = @bitCast(std.mem.readPackedInt(
            u32,
            buffer,
            offset + @bitOffsetOf(Self, "charge"),
            .little,
        ));
    }
};

const MAX_PROJECTILES = 50;
pub const BoardState = extern struct {
    projectile_count: u8 = 0,
    projectiles: [MAX_PROJECTILES]ProjectileState = std.mem.zeroes([MAX_PROJECTILES]ProjectileState),

    const Self = @This();

    pub fn init(count: u8) Self {
        return .{
            .projectile_count = count,
        };
    }

    pub fn encode(self: *const Self, buffer: []u8, offset: usize) void {
        std.mem.writePackedInt(
            u8,
            @ptrCast(buffer[0..]),
            offset + @bitOffsetOf(Self, "projectile_count"),
            self.projectile_count,
            .little,
        );

        const actual_bit_offset = offset + @bitSizeOf(@TypeOf(self.projectile_count));
        for (self.projectiles, 0..) |projectile, index| {
            const local_offset = actual_bit_offset + index * @bitSizeOf(ProjectileState);
            projectile.encode(buffer[0..], local_offset);
        }
    }

    pub fn decode(self: *Self, buffer: []const u8, offset: usize) void {
        self.projectile_count = std.mem.readPackedInt(
            u8,
            @ptrCast(buffer[0..]),
            offset + @bitOffsetOf(Self, "projectile_count"),
            .little,
        );

        const actual_bit_offset = offset + @bitSizeOf(@TypeOf(self.projectile_count));
        for (self.projectiles, 0..) |_, index| {
            const local_offset = actual_bit_offset + index * @bitSizeOf(ProjectileState);
            self.projectiles[index] = ProjectileState.decode(buffer, local_offset);
        }
    }
};

pub const ProjectileState = extern struct {
    id: u32 align(1) = 0,
    owner: u8 align(1) = 0,
    position_x: f32 align(1) = 0.0,
    position_y: f32 align(1) = 0.0,
    velocity_x: f32 align(1) = 0.0,
    velocity_y: f32 align(1) = 0.0,
    charge: f32 align(1) = 0.0,
    extra_mass: f32 align(1) = 0.0, // TODO: add this

    const Self = @This();

    pub fn encode(self: *const Self, buffer: []u8, offset: usize) void {
        std.mem.writePackedInt(
            u32,
            buffer,
            offset + @bitOffsetOf(Self, "id"),
            self.id,
            .little,
        );
        std.mem.writePackedInt(
            u8,
            buffer,
            offset + @bitOffsetOf(Self, "owner"),
            self.owner,
            .little,
        );
        std.mem.writePackedInt(
            u32,
            buffer,
            offset + @bitOffsetOf(Self, "position_x"),
            @bitCast(self.position_x),
            .little,
        );
        std.mem.writePackedInt(
            u32,
            buffer,
            offset + @bitOffsetOf(Self, "position_y"),
            @bitCast(self.position_y),
            .little,
        );
        std.mem.writePackedInt(
            u32,
            buffer,
            offset + @bitOffsetOf(Self, "velocity_x"),
            @bitCast(self.velocity_x),
            .little,
        );
        std.mem.writePackedInt(
            u32,
            buffer,
            offset + @bitOffsetOf(Self, "velocity_y"),
            @bitCast(self.velocity_y),
            .little,
        );
        std.mem.writePackedInt(
            u32,
            buffer,
            offset + @bitOffsetOf(Self, "charge"),
            @bitCast(self.charge),
            .little,
        );
    }

    pub fn decode(buffer: []const u8, offset: usize) Self {
        const id: u32 = std.mem.readPackedInt(
            u32,
            buffer,
            offset + @bitOffsetOf(Self, "id"),
            .little,
        );
        const owner: u8 = std.mem.readPackedInt(
            u8,
            buffer,
            offset + @bitOffsetOf(Self, "owner"),
            .little,
        );
        const position_x: f32 = @bitCast(std.mem.readPackedInt(
            u32,
            buffer,
            offset + @bitOffsetOf(Self, "position_x"),
            .little,
        ));
        const position_y: f32 = @bitCast(std.mem.readPackedInt(
            u32,
            buffer,
            offset + @bitOffsetOf(Self, "position_y"),
            .little,
        ));
        const velocity_x: f32 = @bitCast(std.mem.readPackedInt(
            u32,
            buffer,
            offset + @bitOffsetOf(Self, "velocity_x"),
            .little,
        ));
        const velocity_y: f32 = @bitCast(std.mem.readPackedInt(
            u32,
            buffer,
            offset + @bitOffsetOf(Self, "velocity_y"),
            .little,
        ));
        const charge: f32 = @bitCast(std.mem.readPackedInt(
            u32,
            buffer,
            offset + @bitOffsetOf(Self, "charge"),
            .little,
        ));

        return .{
            .id = id,
            .owner = owner,
            .position_x = position_x,
            .position_y = position_y,
            .velocity_x = velocity_x,
            .velocity_y = velocity_y,
            .charge = charge,
        };
    }
};
