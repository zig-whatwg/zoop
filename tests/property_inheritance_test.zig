const std = @import("std");

// Manually define what the codegen would produce for testing

pub const Person = struct {
    email: []const u8,
    age: u32,
    name: []const u8,

    pub inline fn get_email(self: *@This()) []const u8 {
        return self.email;
    }
    pub inline fn set_email(self: *@This(), value: []const u8) void {
        self.email = value;
    }
    pub inline fn get_age(self: *@This()) u32 {
        return self.age;
    }
    pub inline fn set_age(self: *@This(), value: u32) void {
        self.age = value;
    }
};

pub const Employee = struct {
    super: Person,

    email: []const u8,
    age: u32,
    badge_id: u32,
    department: []const u8,

    pub inline fn get_email(self: *@This()) []const u8 {
        return self.email;
    }
    pub inline fn set_email(self: *@This(), value: []const u8) void {
        self.email = value;
    }
    pub inline fn get_age(self: *@This()) u32 {
        return self.age;
    }
    pub inline fn set_age(self: *@This(), value: u32) void {
        self.age = value;
    }
    pub inline fn get_badge_id(self: *@This()) u32 {
        return self.badge_id;
    }
};

test "property inheritance - child has parent properties" {
    var emp = Employee{
        .super = Person{
            .email = "ignore@example.com",
            .age = 99,
            .name = "Bob",
        },
        .email = "bob@company.com",
        .age = 30,
        .badge_id = 12345,
        .department = "Engineering",
    };

    // Employee should have inherited email property
    try std.testing.expectEqualStrings("bob@company.com", emp.get_email());

    // Employee should have inherited age property
    try std.testing.expectEqual(@as(u32, 30), emp.get_age());

    // Employee should have its own badge_id property
    try std.testing.expectEqual(@as(u32, 12345), emp.get_badge_id());
}

test "property inheritance - modifications work" {
    var emp = Employee{
        .super = Person{
            .email = "ignore",
            .age = 99,
            .name = "Alice",
        },
        .email = "alice@company.com",
        .age = 25,
        .badge_id = 54321,
        .department = "Sales",
    };

    // Modify inherited properties
    emp.set_email("alice.new@company.com");
    emp.set_age(26);

    // Verify changes
    try std.testing.expectEqualStrings("alice.new@company.com", emp.get_email());
    try std.testing.expectEqual(@as(u32, 26), emp.get_age());
}

test "property inheritance - parent properties independent" {
    var person = Person{
        .email = "person@example.com",
        .age = 40,
        .name = "Charlie",
    };

    // Person's properties work
    try std.testing.expectEqualStrings("person@example.com", person.get_email());
    try std.testing.expectEqual(@as(u32, 40), person.get_age());

    // Modify person's properties
    person.set_email("charlie@example.com");
    person.set_age(41);

    try std.testing.expectEqualStrings("charlie@example.com", person.get_email());
    try std.testing.expectEqual(@as(u32, 41), person.get_age());
}
