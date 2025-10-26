const std = @import("std");
const Allocator = std.mem.Allocator;

pub const StringPool = struct {
    map: std.StringHashMap([]const u8),
    allocator: Allocator,

    pub fn init(allocator: Allocator) !*StringPool {
        const pool = try allocator.create(StringPool);
        errdefer allocator.destroy(pool);

        pool.* = .{
            .map = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };

        return pool;
    }

    pub fn deinit(self: *StringPool) void {
        var iter = self.map.valueIterator();
        while (iter.next()) |value| {
            self.allocator.free(value.*);
        }
        self.map.deinit();
        self.allocator.destroy(self);
    }

    pub fn intern(self: *StringPool, string: []const u8) ![]const u8 {
        if (self.map.get(string)) |interned| {
            return interned;
        }

        const copy = try self.allocator.dupe(u8, string);
        try self.map.put(copy, copy);
        return copy;
    }
};

pub const Object = struct {
    ref_count: usize = 1,
    name: []const u8,

    fn init(name: []const u8) Object {
        return .{
            .ref_count = 1,
            .name = name,
        };
    }

    pub fn acquire(self: *Object) void {
        self.ref_count += 1;
    }

    pub fn release(self: *Object) void {
        self.ref_count -= 1;
    }
};

pub const Factory = struct {
    allocator: Allocator,
    string_pool: *StringPool,
    objects: std.ArrayList(*Object),

    pub fn init(allocator: Allocator) !*Factory {
        const factory = try allocator.create(Factory);
        errdefer allocator.destroy(factory);

        const string_pool = try StringPool.init(allocator);
        errdefer string_pool.deinit();

        factory.* = .{
            .allocator = allocator,
            .string_pool = string_pool,
            .objects = std.ArrayList(*Object).init(allocator),
        };

        return factory;
    }

    pub fn deinit(self: *Factory) void {
        for (self.objects.items) |obj| {
            self.allocator.destroy(obj);
        }
        self.objects.deinit();
        self.string_pool.deinit();
        self.allocator.destroy(self);
    }

    pub fn create(self: *Factory, name: []const u8) !*Object {
        const interned_name = try self.string_pool.intern(name);

        const obj = try self.allocator.create(Object);
        obj.* = Object.init(interned_name);

        try self.objects.append(obj);
        return obj;
    }
};

test "factory pattern with string interning" {
    const allocator = std.testing.allocator;

    const factory = try Factory.init(allocator);
    defer factory.deinit();

    const obj1 = try factory.create("shared");
    const obj2 = try factory.create("shared");

    try std.testing.expect(obj1.name.ptr == obj2.name.ptr);
}
