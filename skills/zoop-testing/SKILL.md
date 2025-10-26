# Zoop Testing Skill

## When to use this skill

Load this skill automatically when:
- After making code changes
- Before committing
- Adding new features
- Debugging test failures
- Performance validation
- Working with files in `tests/` directory
- Modifying `build.zig` test configuration

## What this skill provides

This skill ensures Claude can effectively test Zoop by:
- Running the complete test suite (39 tests)
- Understanding test categories and their purposes
- Adding new tests correctly
- Debugging test failures systematically
- Validating zero-overhead performance claims
- Ensuring memory safety and leak detection

## Quick Commands

```bash
# Run all tests
zig build test

# Run performance benchmarks (long-running)
zig build benchmark

# Build only (no tests)
zig build

# Clean and rebuild
rm -rf zig-cache zig-out && zig build test
```

## Test Suite Overview

| Test File | Purpose | Tests |
|-----------|---------|-------|
| `tests/test_mixins.zig` | Mixin functionality | 5 |
| `tests/performance_test.zig` | Zero-overhead validation | 8 |
| `tests/memory_test.zig` | Memory safety | 4 |
| `tests/complex_inheritance_test.zig` | Multi-level inheritance | 6 |
| `tests/property_inheritance_test.zig` | Property generation | 4 |
| `src/root.zig` | Core module tests | 3 |
| `src/class.zig` | ClassConfig tests | 3 |

**Total:** 39 tests (as of v0.2.0)

## Test Categories

### 1. Mixin Tests (`tests/test_mixins.zig`)

Verifies mixin functionality:
- Field flattening
- Method copying
- Parent + mixin combination
- Override detection

**Key assertions:**
```zig
try std.testing.expectEqual(@as(i64, 1000), user.created_at);  // Flattened field
user.updateTimestamp();  // Mixin method available
user.call_save();        // Parent method available
```

### 2. Performance Tests (`tests/performance_test.zig`)

Validates zero-overhead claims:

| Benchmark | Validates |
|-----------|-----------|
| Property getter | Inline property access |
| Method call | Direct vs inherited methods |
| Deep chain access | Multi-level inheritance |
| Object creation | Struct initialization |

**Expected:** All operations < 10ns per call in ReleaseFast

### 3. Memory Tests (`tests/memory_test.zig`)

Ensures no memory leaks:
- Allocation/deallocation tracking
- Init/deinit chains
- Cross-file inheritance cleanup

**Run separately:** `zig build benchmark` (takes 20+ seconds)

### 4. Complex Inheritance (`tests/complex_inheritance_test.zig`)

Tests edge cases:
- Multi-level chains (3+ levels)
- Diamond-like patterns
- Cross-file inheritance
- Method override chains

## Adding New Tests

### 1. Create Test File

```zig
// tests/test_feature.zig
const std = @import("std");

test "feature works correctly" {
    // Arrange
    const value = 42;
    
    // Act
    const result = someFunction(value);
    
    // Assert
    try std.testing.expectEqual(expected, result);
}
```

### 2. Add to `build.zig`

```zig
const feature_test = b.addTest(.{
    .root_module = b.createModule(.{
        .root_source_file = b.path("tests/test_feature.zig"),
        .target = target,
        .optimize = optimize,
    }),
});
const run_feature_test = b.addRunArtifact(feature_test);
test_step.dependOn(&run_feature_test.step);
```

### 3. Run Tests

```bash
zig build test
```

## Debugging Test Failures

### Check Generated Code

```bash
# View what codegen produces
ls -la .zig-cache/zoop-generated/
cat .zig-cache/zoop-generated/test_mixins.zig
```

### Add Debug Output

```zig
test "debug failing test" {
    const value = getValue();
    std.debug.print("Value: {}\n", .{value});
    try std.testing.expectEqual(42, value);
}
```

### Run Single Test

```bash
# Run specific test file
zig test tests/test_mixins.zig
```

## Common Test Patterns

### Testing Generated Structures

```zig
test "generated struct has correct fields" {
    const Dog = struct {
        name: []const u8,
        age: u8,
        breed: []const u8,
    };
    
    const dog = Dog{
        .name = "Max",
        .age = 3,
        .breed = "Lab",
    };
    
    try std.testing.expectEqualStrings("Max", dog.name);
}
```

### Testing Method Availability

```zig
test "inherited methods available" {
    var dog = Dog{
        .name = "Max",
        .age = 3,
        .breed = "Lab",
    };
    
    // Should compile without error
    dog.eat();  // From Animal
}
```

### Testing Override Detection

```zig
test "child overrides prevent method copying" {
    // If Child.speak() exists, call_speak() should NOT be generated
    const hasCallSpeak = @hasDecl(Dog, "call_speak");
    try std.testing.expect(!hasCallSpeak);
}
```

## Performance Testing

### Benchmark Template

```zig
test "benchmark operation" {
    const iterations = 1_000_000;
    const start = std.time.nanoTimestamp();
    
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        // Operation to benchmark
        _ = object.method();
    }
    
    const end = std.time.nanoTimestamp();
    const elapsed = @as(u64, @intCast(end - start));
    const ns_per_op = elapsed / iterations;
    
    std.debug.print("{} ns/op\n", .{ns_per_op});
    try std.testing.expect(ns_per_op < 10);  // Should be < 10ns
}
```

## Continuous Integration

### Pre-Commit Checks

```bash
#!/bin/bash
# .git/hooks/pre-commit

zig build test || exit 1
echo "✓ All tests pass"
```

### CI Pipeline (GitHub Actions example)

```yaml
- name: Run tests
  run: zig build test
  
- name: Run benchmarks
  run: zig build benchmark
```

## Test Maintenance

### When to Update Tests

- Architecture changes → Update all affected tests
- New features → Add new test file
- Bug fixes → Add regression test
- Performance changes → Update benchmark expectations

### Test Coverage Goals

- ✅ All public APIs tested
- ✅ All inheritance patterns covered
- ✅ All error paths tested
- ✅ Performance validated

## Troubleshooting

### "Test failed: expected X, got Y"
1. Check generated code in `.zig-cache/zoop-generated/`
2. Verify source file is correct
3. Rebuild: `zig build`

### "Out of memory"
- Reduce benchmark iterations
- Run memory benchmark separately: `zig build benchmark`

### "File not found"
- Ensure test file is in `tests/` directory
- Check `build.zig` includes the test
- Verify paths are relative to project root

## Common Anti-Patterns to Avoid

### ❌ Not Using `defer` for Cleanup

```zig
// ❌ BAD
test "leaky test" {
    var list = ArrayList(u8).init(allocator);
    // Forgot defer - leaks memory!
    try list.append(42);
}

// ✅ GOOD
test "clean test" {
    var list: ArrayList(u8) = .empty;
    defer list.deinit(allocator);  // Always cleaned up
    try list.append(allocator, 42);
}
```

### ❌ Testing Generated Code Directly

```zig
// ❌ BAD - fragile to codegen changes
const generated = @import("../.zig-cache/zoop-generated/example.zig");

// ✅ GOOD - test behavior, not implementation
test "inherited method works" {
    var dog = Dog{ .name = "Max", .age = 3, .breed = "Lab" };
    dog.eat();  // Should compile and work
}
```

### ❌ Benchmarks Without Assertions

```zig
// ❌ BAD - just prints, doesn't validate
std.debug.print("{} ns/op\n", .{ns_per_op});

// ✅ GOOD - validates performance claim
std.debug.print("{} ns/op\n", .{ns_per_op});
try std.testing.expect(ns_per_op < 10);  // Must be < 10ns
```

## Quick Reference

**Run all tests**: `zig build test`

**Run benchmarks**: `zig build benchmark` (20+ seconds)

**Test count**: 39 tests across 7+ files

**Key patterns**:
- Use `std.testing.allocator` (detects leaks)
- Always `defer` cleanup
- Test behavior, not implementation
- Validate performance with assertions

**Debugging**:
- Check `.zig-cache/zoop-generated/` for generated code
- Add `std.debug.print` for inspection
- Run single file: `zig test tests/file.zig`

## References

- `build.zig` - Test configuration
- `tests/` - All test files
- `zig build --help` - Available build commands
