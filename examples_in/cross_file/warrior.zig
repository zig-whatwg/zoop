const std = @import("std");
const zoop = @import("zoop");
const player = @import("player.zig");

pub const Warrior = zoop.class(struct {
    pub const extends = player.Player;

    pub const properties = .{
        .weapon = .{
            .type = []const u8,
            .access = .read_write,
        },
        .armor = .{
            .type = u32,
            .access = .read_write,
        },
        .rage = .{
            .type = u32,
            .access = .read_only,
        },
    };

    strength: u32,
    defense: u32,

    pub fn init(id_val: u64, timestamp: u64, warrior_name: []const u8, weapon_name: []const u8) Warrior {
        return Warrior{
            .id = id_val,
            .created_at = timestamp,
            .active = true,
            .name = warrior_name,
            .health = 150,
            .max_health = 150,
            .level = 1,
            .experience = 0,
            .weapon = weapon_name,
            .armor = 50,
            .rage = 0,
            .strength = 20,
            .defense = 15,
        };
    }

    pub fn attack(self: *Warrior, target_name: []const u8) void {
        const damage = self.strength + (self.rage / 10);
        self.rage = @min(self.rage + 10, 100);
        std.debug.print("{s} attacks {s} with {s} for {} damage! (Rage: {})\n", .{
            self.name,
            target_name,
            self.weapon,
            damage,
            self.rage,
        });
    }

    pub fn defend(self: *Warrior) void {
        const damage_reduction = self.defense + self.armor;
        self.rage = @max(self.rage -| 5, 0);
        std.debug.print("{s} defends! (Damage reduction: {}, Rage: {})\n", .{
            self.name,
            damage_reduction,
            self.rage,
        });
    }

    pub fn berserk(self: *Warrior) void {
        if (self.rage >= 50) {
            self.rage = 100;
            const bonus_damage = self.strength * 2;
            std.debug.print("{s} goes BERSERK! Bonus damage: {}\n", .{
                self.name,
                bonus_damage,
            });
        } else {
            std.debug.print("{s} needs more rage! (Current: {}/50)\n", .{
                self.name,
                self.rage,
            });
        }
    }

    pub fn display(self: *const Warrior) void {
        std.debug.print("Warrior: {s} (ID: {}, Level: {}, HP: {}/{}, Weapon: {s}, Armor: {}, Rage: {}, STR: {}, DEF: {})\n", .{
            self.name,
            self.id,
            self.level,
            self.health,
            self.max_health,
            self.weapon,
            self.armor,
            self.rage,
            self.strength,
            self.defense,
        });
    }
});
