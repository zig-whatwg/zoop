const std = @import("std");
const zoop = @import("zoop");

// Level 1: Base class with custom init validation
pub const Entity = zoop.class(struct {
    pub const properties = .{
        .id = .{
            .type = u64,
            .access = .read_only,
        },
    };

    pub fn init(allocator: std.mem.Allocator, id: u64) !Entity {
        // Custom validation logic
        if (id == 0) return error.InvalidId;
        if (id > 999999) return error.IdTooLarge;

        std.debug.print("[Entity.init] Creating entity with id={}\n", .{id});

        return try Entity.initFields(allocator, &.{
            .id = id,
        });
    }

    fn initFields(allocator: std.mem.Allocator, fields: *const struct { id: u64 }) !Entity {
        return .{
            .allocator = allocator,
            .id = fields.id,
        };
    }
});

// Level 2: Named entity adds a name field
pub const NamedEntity = zoop.class(struct {
    pub const extends = Entity;

    name: []const u8,
});

// Level 3: User adds email and active status
pub const User = zoop.class(struct {
    pub const extends = NamedEntity;

    pub const properties = .{
        .email = .{
            .type = []const u8,
            .access = .read_write,
        },
    };

    active: bool,
});
