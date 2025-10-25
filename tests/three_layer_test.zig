const std = @import("std");
const classes = @import("fixtures/three_layer_generated.zig");

test "three layer inheritance - property access" {
    var dog = classes.Dog{
        .super = classes.Mammal{
            .super = classes.Animal{
                .species = "Canis familiaris",
                .age = 3,
                .name = "Buddy",
            },
            .species = "Canis familiaris",
            .age = 3,
            .fur_color = "Golden",
            .warm_blooded = true,
        },
        .fur_color = "Golden",
        .species = "Canis familiaris",
        .age = 3,
        .breed = "Golden Retriever",
        .good_boy = true,
    };

    // Test property getters from all layers
    try std.testing.expectEqualStrings("Canis familiaris", dog.get_species());
    try std.testing.expectEqual(@as(u32, 3), dog.get_age());
    try std.testing.expectEqualStrings("Golden", dog.get_fur_color());
    try std.testing.expectEqualStrings("Golden Retriever", dog.get_breed());
}

test "three layer inheritance - property modification" {
    var dog = classes.Dog{
        .super = classes.Mammal{
            .super = classes.Animal{
                .species = "Canis familiaris",
                .age = 3,
                .name = "Buddy",
            },
            .species = "Canis familiaris",
            .age = 3,
            .fur_color = "Golden",
            .warm_blooded = true,
        },
        .fur_color = "Golden",
        .species = "Canis familiaris",
        .age = 3,
        .breed = "Golden Retriever",
        .good_boy = true,
    };

    // Test read-write properties
    dog.set_age(4);
    try std.testing.expectEqual(@as(u32, 4), dog.get_age());

    dog.set_fur_color("Light Golden");
    try std.testing.expectEqualStrings("Light Golden", dog.get_fur_color());

    // Read-only properties (species, breed) don't have setters
    // This is enforced at compile time
}

test "three layer inheritance - method calls" {
    const dog = classes.Dog{
        .super = classes.Mammal{
            .super = classes.Animal{
                .species = "Canis familiaris",
                .age = 3,
                .name = "Buddy",
            },
            .species = "Canis familiaris",
            .age = 3,
            .fur_color = "Golden",
            .warm_blooded = true,
        },
        .fur_color = "Golden",
        .species = "Canis familiaris",
        .age = 3,
        .breed = "Golden Retriever",
        .good_boy = true,
    };

    // Dog's own methods work
    dog.bark();
    dog.speak();

    // Inherited methods via wrappers
    dog.call_nurse();
    const age = dog.call_getAge();
    try std.testing.expectEqual(@as(u32, 3), age);
}

test "three layer inheritance - field access" {
    const dog = classes.Dog{
        .super = classes.Mammal{
            .super = classes.Animal{
                .species = "Canis familiaris",
                .age = 3,
                .name = "Buddy",
            },
            .species = "Canis familiaris",
            .age = 3,
            .fur_color = "Golden",
            .warm_blooded = true,
        },
        .fur_color = "Golden",
        .species = "Canis familiaris",
        .age = 3,
        .breed = "Golden Retriever",
        .good_boy = true,
    };

    // Regular fields accessed via super chain
    try std.testing.expectEqualStrings("Buddy", dog.super.super.name);
    try std.testing.expectEqual(true, dog.super.warm_blooded);
    try std.testing.expectEqual(true, dog.good_boy);
}

test "three layer inheritance - mammal layer" {
    var mammal = classes.Mammal{
        .super = classes.Animal{
            .species = "Felis catus",
            .age = 5,
            .name = "Whiskers",
        },
        .species = "Felis catus",
        .age = 5,
        .fur_color = "Orange",
        .warm_blooded = true,
    };

    // Mammal has properties from Animal
    try std.testing.expectEqualStrings("Felis catus", mammal.get_species());
    try std.testing.expectEqual(@as(u32, 5), mammal.get_age());

    // Mammal has its own property
    try std.testing.expectEqualStrings("Orange", mammal.get_fur_color());

    // Mammal can modify read-write properties
    mammal.set_age(6);
    mammal.set_fur_color("White");
    try std.testing.expectEqual(@as(u32, 6), mammal.get_age());
    try std.testing.expectEqualStrings("White", mammal.get_fur_color());
}
