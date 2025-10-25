# Testing in Zoop

All tests are located in the `tests/` directory.

## Quick Summary

**29 tests total, all passing**
- ✅ Property inheritance (2 & 3 layers)
- ✅ Complex inheritance scenarios (5 levels deep)
- ✅ Zero memory leaks (automatically verified)
- ✅ Zero-cost abstraction (benchmarked)

See [TEST_SUMMARY.md](TEST_SUMMARY.md) for detailed results.

## Running Tests

```bash
# Run all tests (29 total)
zig build test

# Run specific test files
zig test tests/complex_inheritance_test.zig  # Complex scenarios
zig test tests/memory_test.zig              # Memory leak detection
zig test tests/performance_test.zig         # Benchmarks
```

## Test Files

| File | Tests | Description |
|------|-------|-------------|
| `basic_test.zig` | 2 | Sanity checks |
| `property_inheritance_test.zig` | 3 | 2-layer property inheritance |
| `three_layer_test.zig` | 5 | 3-layer full inheritance |
| `complex_inheritance_test.zig` | 5 | Edge cases (deep chains, branches, arrays) |
| `memory_test.zig` | 6 | Memory leak detection |
| `performance_test.zig` | 8 | Zero-cost abstraction verification |

## Test Highlights

### Complex Inheritance (5 tests)
- Multiple branches from same parent
- 5-level deep inheritance chains
- 8 properties across 2 levels
- Arrays of inherited objects

### Memory Safety (6 tests)
- Heap allocations (parent & child)
- ArrayList with 100 objects
- Large stack allocations (3KB+)
- **Result: Zero memory leaks detected**

### Performance (8 tests)
```
Property getter:     ~5 ns/op  (1M iterations)
Method call:         ~4 ns/op  (1M iterations)
Deep chain (5 lvls): ~4 ns/op  (no overhead!)
Object creation:     ~5 ns/op  (100K objects)
```
**Result: Zero-cost abstraction verified**

## Test Fixtures

`tests/fixtures/` contains example code showing the transformation.

### `three_layer_source.txt`
Source code using `zoop.class()` (INPUT to codegen).

### `three_layer_generated.zig`
Generated plain structs (OUTPUT from codegen).

## Adding Tests

1. Create `tests/your_test.zig`
2. Write test blocks: `test "description" { ... }`
3. Add to `build.zig` test list
4. Run with `zig build test`

## Test Coverage

✅ **Implemented & Tested:**
- Property inheritance (2-5 layers)
- Property getters/setters
- Read-only vs read-write access
- Method inheritance & wrappers
- Override detection
- Field access via super chain
- Deep inheritance (5 levels)
- Multiple branches
- Complex structures (8+ properties)
- Memory safety (automatic leak detection)
- Performance (zero-cost verification)

❌ **Not Tested Yet:**
- Parser edge cases
- Error conditions
- Mixin system (not implemented)
- Cross-file inheritance (not implemented)
