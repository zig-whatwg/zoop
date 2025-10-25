# Zoop Project Structure

```
zoop/
├── README.md                          # Main documentation
├── build.zig                          # Build configuration
├── build.zig.zon                      # Package manifest
│
├── Documentation/
│   ├── API_REFERENCE.md               # Complete API reference
│   ├── IMPLEMENTATION.md              # Architecture deep-dive
│   ├── CONSUMER_USAGE.md              # How to use Zoop in your project
│   ├── LIBRARY_USAGE.md               # Library integration guide
│   ├── AUTOMATIC_BUILD_CODEGEN.md     # Build system documentation
│   ├── CRITICAL_ISSUES.md             # Known issues & limitations
│   ├── REMAINING_ISSUES.md            # TODO list (9 items)
│   ├── TESTING.md                     # How to run tests
│   ├── TEST_SUMMARY.md                # Test results & benchmarks
│   └── plan.md                        # Original design (historical)
│
├── src/                               # Source code
│   ├── root.zig                       # Library entry point
│   ├── main.zig                       # Example executable
│   ├── codegen.zig                    # Code generator core
│   ├── codegen_main.zig               # Codegen CLI
│   ├── class.zig                      # Class type definitions
│   ├── macro.zig                      # Macro system (conceptual)
│   └── build_impl.zig                 # Build system integration
│
└── tests/                             # Test suite (31 tests)
    ├── README.md                      # Test documentation
    ├── basic_test.zig                 # Sanity tests (2)
    ├── property_inheritance_test.zig  # 2-layer tests (3)
    ├── three_layer_test.zig           # 3-layer tests (5)
    ├── complex_inheritance_test.zig   # Complex scenarios (5)
    ├── memory_test.zig                # Leak detection (6)
    ├── performance_test.zig           # Benchmarks (8)
    ├── memory_benchmark.zig           # 20s stress test (2)
    └── fixtures/
        ├── three_layer_source.txt     # Example source (INPUT)
        └── three_layer_generated.zig  # Example output (OUTPUT)
```

## Generated Artifacts

```
zig-out/
└── bin/
    └── zoop-codegen                   # Code generator executable

.zig-cache/                            # Build cache (gitignored)
```

## File Counts

- **Source files**: 7 Zig files
- **Test files**: 8 Zig files (31 tests total)
- **Documentation**: 10 Markdown files
- **Examples**: 2 fixture files

## Key Entry Points

| File | Purpose |
|------|---------|
| `README.md` | Start here - overview and quick start |
| `IMPLEMENTATION.md` | Understand how Zoop works |
| `src/codegen.zig` | Core code generation logic |
| `tests/` | Examples of generated code |
| `zig build` | Build everything |
| `zig build test` | Run all tests |
| `zig build benchmark` | Run 20s memory stress test |
| `zig build codegen` | Build code generator tool |

## Documentation Reading Order

1. **README.md** - Overview and examples
2. **IMPLEMENTATION.md** - Architecture (how it works)
3. **CONSUMER_USAGE.md** - How to use in your project
4. **API_REFERENCE.md** - Complete API docs
5. **TESTING.md** - Test suite overview
6. **CRITICAL_ISSUES.md** - Known limitations
7. **REMAINING_ISSUES.md** - Future work
