const std = @import("std");
const zoop = @import("zoop");

pub const Animal = zoop.class(struct {
    name: []const u8,

    pub fn makeSound(self: *Animal) void {
        std.debug.print("{s} makes a sound\n", .{self.name});
    }
});

pub const Dog = zoop.class(struct {
    pub const extends = Animal;

    breed: []const u8,

    pub fn bark(self: *Dog) void {
        std.debug.print("{s} the {s} barks!\n", .{ self.name, self.breed });
    }
});

pub fn main() void {
    var dog = Dog{
        .name = "Buddy",
        .breed = "Golden Retriever",
    };

    dog.makeSound();
    dog.bark();
}
