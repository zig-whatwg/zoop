const std = @import("std");

// This is what zoop-codegen GENERATES from the source file

pub const Animal = struct {
    species: []const u8,
    age: u32,
    name: []const u8,

    pub fn speak(self: *const Animal) void {
        std.debug.print("{s} makes a sound\n", .{self.name});
    }
    pub fn getAge(self: *const Animal) u32 {
        return self.age;
    }

    pub inline fn get_species(self: *@This()) []const u8 {
        return self.species;
    }
    pub inline fn get_age(self: *@This()) u32 {
        return self.age;
    }
    pub inline fn set_age(self: *@This(), value: u32) void {
        self.age = value;
    }
};

pub const Mammal = struct {
    super: Animal,

    species: []const u8,
    age: u32,
    fur_color: []const u8,
    warm_blooded: bool,

    pub fn nurse(self: *const Mammal) void {
        std.debug.print("{s} is nursing offspring\n", .{self.super.name});
    }

    pub inline fn call_speak(self: *const Mammal) void {
        self.super.speak();
    }
    pub inline fn call_getAge(self: *const Mammal) u32 {
        return self.super.getAge();
    }

    pub inline fn get_species(self: *@This()) []const u8 {
        return self.species;
    }
    pub inline fn get_age(self: *@This()) u32 {
        return self.age;
    }
    pub inline fn set_age(self: *@This(), value: u32) void {
        self.age = value;
    }
    pub inline fn get_fur_color(self: *@This()) []const u8 {
        return self.fur_color;
    }
    pub inline fn set_fur_color(self: *@This(), value: []const u8) void {
        self.fur_color = value;
    }
};

pub const Dog = struct {
    super: Mammal,

    fur_color: []const u8,
    species: []const u8,
    age: u32,
    breed: []const u8,
    good_boy: bool,

    pub fn bark(self: *const Dog) void {
        std.debug.print("{s} barks: Woof!\n", .{self.super.super.name});
    }
    pub fn speak(self: *const Dog) void {
        std.debug.print("{s} the {s} barks!\n", .{ self.super.super.name, self.breed });
    }

    pub inline fn call_nurse(self: *const Dog) void {
        self.super.nurse();
    }
    pub inline fn call_getAge(self: *const Dog) u32 {
        return self.super.call_getAge();
    }

    pub inline fn get_fur_color(self: *@This()) []const u8 {
        return self.fur_color;
    }
    pub inline fn set_fur_color(self: *@This(), value: []const u8) void {
        self.fur_color = value;
    }
    pub inline fn get_species(self: *@This()) []const u8 {
        return self.species;
    }
    pub inline fn get_age(self: *@This()) u32 {
        return self.age;
    }
    pub inline fn set_age(self: *@This(), value: u32) void {
        self.age = value;
    }
    pub inline fn get_breed(self: *@This()) []const u8 {
        return self.breed;
    }
};
