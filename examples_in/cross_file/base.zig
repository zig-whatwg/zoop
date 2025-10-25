const std = @import("std");
const zoop = @import("zoop");

pub const Entity = zoop.class(struct {
    pub const properties = .{
        .id = .{
            .type = u64,
            .access = .read_only,
        },
        .created_at = .{
            .type = u64,
            .access = .read_only,
        },
    };

    active: bool,

    pub fn init(id_val: u64, timestamp: u64) Entity {
        return Entity{
            .id = id_val,
            .created_at = timestamp,
            .active = true,
        };
    }

    pub fn display(self: *const Entity) void {
        std.debug.print("Entity ID: {} (Created: {}, Active: {})\n", .{
            self.id,
            self.created_at,
            self.active,
        });
    }

    pub fn deactivate(self: *Entity) void {
        self.active = false;
    }
});
