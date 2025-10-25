# Zoop Tests

This directory contains all test files for the Zoop OOP system.

## Test Structure

```
tests/
├── README.md                          # This file
├── basic_test.zig                     # Basic sanity tests (2 tests)
├── property_inheritance_test.zig      # Property inheritance tests (3 tests)
├── three_layer_test.zig               # Three-layer inheritance tests (5 tests)
├── complex_inheritance_test.zig       # Complex scenarios (5 tests)
├── memory_test.zig                    # Memory leak tests (6 tests)
├── performance_test.zig               # Performance benchmarks (8 tests)
├── memory_benchmark.zig               # 20+ second memory leak stress test (2 tests)
└── fixtures/
    ├── three_layer_source.txt         # Source code example
    └── three_layer_generated.zig      # Generated code fixture
```

## Running Tests

```bash
# Run all tests (29 total, fast)
zig build test

# Run memory leak benchmark (20+ seconds)
zig build benchmark

# Run specific test file
zig test tests/complex_inheritance_test.zig
zig test tests/memory_test.zig
zig test tests/performance_test.zig
zig test tests/memory_benchmark.zig
```

## Test Coverage

### ✅ Property Inheritance Tests (`property_inheritance_test.zig` - 3 tests)

Tests two-layer property inheritance:
- Child classes have parent properties copied
- Getters and setters work correctly
- Parent and child properties are independent

### ✅ Three-Layer Inheritance Tests (`three_layer_test.zig` - 5 tests)

Tests three-layer property and method inheritance:
- Property access through all layers
- Property modification (read-write vs read-only)
- Method calls (own methods + inherited wrappers)
- Field access via `super.super.field`
- Middle layer works independently

### ✅ Complex Inheritance Tests (`complex_inheritance_test.zig` - 5 tests)

Tests complex inheritance scenarios:
- **Multiple branches from same parent** - Two different child classes from one parent
- **Deep inheritance (5 levels)** - Very deep inheritance chains
- **Property override at different levels** - Each level has its own copy
- **Complex struct with many properties** - 8 properties across 2 levels
- **Array of inherited objects** - 10 objects in array with proper initialization

### ✅ Memory Tests (`memory_test.zig` - 6 tests)

Tests for memory leaks and allocation safety:
- **Simple allocation** - Parent class with heap allocation
- **Inherited allocation** - Child class with multiple allocations
- **Multiple allocations** - Array of allocated objects
- **ArrayList of inherited objects** - 100 objects in ArrayList, all properly freed
- **Stack allocation** - No heap usage at all
- **Large stack allocation** - Large structs (3KB+) on stack

All tests use `std.testing.allocator` which **detects memory leaks automatically**.

### ✅ Memory Benchmark (`memory_benchmark.zig` - 2 tests)

Long-running stress tests that measure **actual process memory** over 20+ seconds:

**Test 1: 20-Second Leak Test**
- Creates and destroys 450K+ objects over 20 seconds
- Each batch: 1000 objects (1KB parent + 2KB child = ~3.5KB per object)
- Measures process RSS (Resident Set Size) every 2 seconds
- Verifies memory returns to baseline after GC
- Reports: created, destroyed, current memory, delta from baseline

**Example output:**
```
Time | Created | Destroyed | Memory    | Delta
-----|---------|-----------|-----------|-------------
   2s |   47000 |     47000 |   1.91 MB | +160.00 KB
   4s |   94000 |     94000 |   1.95 MB | +208.00 KB
  ...
  20s |  458000 |    458000 |   2.16 MB | +416.00 KB

✅ PASS: Memory returned to baseline (within 1.00 MB)
```

**Test 2: Aggressive Allocation**
- Creates/destroys large objects (600KB each) for 10 seconds
- 80K+ objects processed
- Each object: 100KB parent + 500KB child
- Reports memory every 1000 objects

**Result: Zero memory leaks detected in both tests**

### ✅ Performance Tests (`performance_test.zig` - 8 tests)

Benchmarks to verify zero-cost abstraction:
- **Property access overhead** - 1M iterations, ~5 ns/op
- **Method call overhead** - 1M iterations through wrapper, ~4 ns/op
- **Direct vs getter** - Confirms inline optimization (0-3 ns difference)
- **Deep chain access (5 levels)** - 1M iterations, ~4 ns/op (no overhead!)
- **Object creation** - 100K objects, ~5 ns/op
- **Setter operations** - 1M iterations, ~2 ns/op
- **Array access pattern** - 10K iterations over 1000 objects
- **Zero-cost abstraction verification** - Compile-time guarantee check

**Key findings:**
- ✅ Property getters have **zero overhead** when inlined
- ✅ Method wrappers have **~1 ns overhead** (negligible)
- ✅ Deep inheritance (5 levels) has **no measurable overhead**
- ✅ Object creation is extremely fast (~5 ns)

## Fixtures

The `fixtures/` directory contains example code showing the transformation from source to generated code.

### `three_layer_source.txt`

Shows what a **user would write** using `zoop.class()` syntax:
```zig
const Animal = zoop.class(struct {
    pub const properties = .{ .species = ... };
    name: []const u8,
});
```

This is the **INPUT** to the codegen system.

### `three_layer_generated.zig`

Shows what **zoop-codegen produces** as output:
```zig
pub const Animal = struct {
    species: []const u8,
    name: []const u8,
    pub inline fn get_species(...) { ... }
};
```

This is the **OUTPUT** from the codegen system. This is what you import and use in your code.

**The transformation:** `zoop.class()` → codegen → plain structs with generated methods

This fixture is used by `three_layer_test.zig` to test the runtime behavior of generated code.

## Adding New Tests

1. Create a new `*_test.zig` file in this directory
2. Import fixtures if needed: `@import("fixtures/your_fixture.zig")`
3. Write test blocks: `test "description" { ... }`
4. Run with `zig test tests/your_test.zig`

## Test Naming Conventions

- Test files: `feature_test.zig` (e.g., `property_inheritance_test.zig`)
- Test names: `"feature - specific case"` (e.g., `"property inheritance - child has parent properties"`)
- Fixtures: `feature_fixture.zig` or `feature_generated.zig`

## What's NOT Tested Yet

See [REMAINING_ISSUES.md](../REMAINING_ISSUES.md) for features that need test coverage:
- Parser edge cases
- Error conditions
- Circular inheritance detection
- Mixin system (not implemented)
- Cross-file inheritance (not implemented)
- Performance benchmarks
