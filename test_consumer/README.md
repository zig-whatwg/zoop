# Test Consumer for Zoop

This is a working example of how to use Zoop in an external project.

## Structure

- `src/main.zig` - Source code with `zoop.class()` definitions
- `src_generated/main.zig` - Generated code (auto-created by build)
- `build.zig` - Build configuration integrating zoop-codegen

## How It Works

1. Source code uses `zoop.class()` as markers
2. Build runs `zoop-codegen` to generate enhanced code  
3. Executable is built from generated code, not source

## Running

```bash
zig build run
```

## Key Points

**Source code** (`src/main.zig`):
```zig
pub const Dog = zoop.class(struct {
    pub const extends = Animal,
    breed: []const u8,
});
```

**Generated code** (`src_generated/main.zig` - auto-created):
```zig
pub const Dog = struct {
    name: []const u8,  // From Animal (flattened)
    age: u8,           // From Animal (flattened)
    breed: []const u8,
    
    // Inherited methods copied directly (zero overhead)
    pub fn makeSound(self: *Dog) void {
        std.debug.print("{s} makes a sound\n", .{self.name});
    }
};
```

**Build integration** (`build.zig`):
- Get zoop dependency and codegen tool
- Run codegen on `src/`, output to `src_generated/`
- Build executable from `src_generated/main.zig`
- Make compilation depend on codegen step
