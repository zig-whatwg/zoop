const std = @import("std");
const zoop = @import("zoop");
const base = @import("base.zig");

pub const Player = zoop.class(struct {
    pub const extends = base.Entity;

    pub const properties = .{
        .name = .{
            .type = []const u8,
            .access = .read_only,
        },
        .health = .{
            .type = i32,
            .access = .read_write,
        },
        .max_health = .{
            .type = i32,
            .access = .read_only,
        },
    };

    level: u32,
    experience: u32,

    pub fn init(id_val: u64, timestamp: u64, player_name: []const u8, max_hp: i32) Player {
        return Player{
            .id = id_val,
            .created_at = timestamp,
            .active = true,
            .name = player_name,
            .health = max_hp,
            .max_health = max_hp,
            .level = 1,
            .experience = 0,
        };
    }

    pub fn heal(self: *Player, amount: i32) void {
        self.health = @min(self.health + amount, self.max_health);
        std.debug.print("{s} healed for {} HP (now {}/{})\n", .{
            self.name,
            amount,
            self.health,
            self.max_health,
        });
    }

    pub fn takeDamage(self: *Player, amount: i32) void {
        self.health = @max(self.health - amount, 0);
        std.debug.print("{s} took {} damage (now {}/{})\n", .{
            self.name,
            amount,
            self.health,
            self.max_health,
        });
    }

    pub fn gainExperience(self: *Player, xp: u32) void {
        self.experience += xp;
        if (self.experience >= self.level * 100) {
            self.level += 1;
            self.experience = 0;
            std.debug.print("{s} leveled up to level {}!\n", .{ self.name, self.level });
        }
    }

    pub fn display(self: *const Player) void {
        std.debug.print("Player: {s} (ID: {}, Level: {}, HP: {}/{}, XP: {})\n", .{
            self.name,
            self.id,
            self.level,
            self.health,
            self.max_health,
            self.experience,
        });
    }
});
