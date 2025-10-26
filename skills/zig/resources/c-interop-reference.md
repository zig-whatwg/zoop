# C Interoperability Reference

## Importing C Headers

```zig
const c = @cImport({
    // Include headers
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("string.h");
    
    // Define macros before including
    @cDefine("_GNU_SOURCE", "1");
    @cDefine("MY_CONSTANT", "42");
});

// Use C functions
pub fn main() void {
    _ = c.printf("Hello from C!\n");
    
    const ptr = c.malloc(100);
    defer c.free(ptr);
}
```

## C Types

```zig
// C primitive types
const c_char_type: c_char = 0;
const c_short_type: c_short = 0;
const c_int_type: c_int = 0;
const c_long_type: c_long = 0;
const c_longlong_type: c_longlong = 0;

const c_uchar_type: c_uchar = 0;
const c_ushort_type: c_ushort = 0;
const c_uint_type: c_uint = 0;
const c_ulong_type: c_ulong = 0;
const c_ulonglong_type: c_ulonglong = 0;

const c_float_type: c_float = 0.0;
const c_double_type: c_double = 0.0;
const c_longdouble_type: c_longdouble = 0.0;

// C pointer types
const c_ptr_type: [*c]u8 = null; // C pointer (nullable, arithmetic)
const c_array: [*c]const u8 = "hello"; // C string
```

## extern Declarations

```zig
// Declare C functions without headers
extern "c" fn printf(format: [*:0]const u8, ...) c_int;
extern "c" fn malloc(size: usize) ?*anyopaque;
extern "c" fn free(ptr: ?*anyopaque) void;

pub fn example() void {
    const ptr = malloc(100);
    defer free(ptr);
    
    _ = printf("Value: %d\n", 42);
}

// Extern variables
extern var errno: c_int;

pub fn checkErrno() c_int {
    return errno;
}
```

## export for C ABI

```zig
// Export Zig functions for C
export fn add(a: c_int, b: c_int) c_int {
    return a + b;
}

// Export with custom name
export fn zigMultiply(a: c_int, b: c_int) c_int {
    return a * b;
}
// In C: extern int zigMultiply(int a, int b);

// Export variables
export var global_counter: c_int = 0;

// Explicit calling convention
export fn callback() callconv(.C) void {
    // Called from C
}
```

## Calling Conventions

```zig
// C calling convention
fn cCallback(value: c_int) callconv(.C) void {
    // Implementation
}

// Other conventions
fn stdcallFunc() callconv(.Stdcall) void {} // Windows
fn fastcallFunc() callconv(.Fastcall) void {} // Optimized
fn nakedFunc() callconv(.Naked) void {} // No prologue/epilogue

// Default Zig convention (not C-compatible)
fn zigFunc() void {
    // Zig's optimized calling convention
}
```

## C Struct Compatibility

```zig
// extern struct - C-compatible layout
const CPoint = extern struct {
    x: c_int,
    y: c_int,
};
// Matches: struct Point { int x; int y; };

// Regular Zig struct (may be reordered)
const ZigPoint = struct {
    x: i32,
    y: i32,
};

// packed struct - explicit bit layout
const BitField = packed struct {
    flag1: bool,
    flag2: bool,
    value: u6,
};

// C ABI compatibility
const CCompatible = extern struct {
    data: [*c]u8,
    len: usize,
    capacity: usize,
};
```

## Opaque Types

```zig
// For C pointers you don't dereference
const FILE = opaque {};
const pthread_t = opaque {};

extern "c" fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*FILE;
extern "c" fn fclose(file: *FILE) c_int;
extern "c" fn fprintf(file: *FILE, fmt: [*:0]const u8, ...) c_int;

pub fn writeToFile() void {
    const file = fopen("output.txt", "w") orelse return;
    defer _ = fclose(file);
    
    _ = fprintf(file, "Hello, %s!\n", "World");
}
```

## C String Handling

```zig
const std = @import("std");

// Null-terminated string literals
const c_str: [*:0]const u8 = "hello";

// Zig to C string
fn zigToCString(allocator: std.mem.Allocator, zig_str: []const u8) ![*:0]u8 {
    const c_string = try allocator.allocSentinel(u8, zig_str.len, 0);
    @memcpy(c_string[0..zig_str.len], zig_str);
    return c_string;
}

// C to Zig string
fn cToZigString(c_str: [*:0]const u8) []const u8 {
    return std.mem.span(c_str);
}

// C string functions
const c = @cImport(@cInclude("string.h"));

pub fn stringExample() void {
    const str1: [*:0]const u8 = "hello";
    const str2: [*:0]const u8 = "world";
    
    const len = c.strlen(str1);
    const cmp = c.strcmp(str1, str2);
    
    var buffer: [100:0]u8 = undefined;
    _ = c.strcpy(&buffer, str1);
}
```

## Variadic Functions

```zig
const c = @cImport(@cInclude("stdio.h"));

// Calling C varargs
pub fn printFormatted() void {
    _ = c.printf("Int: %d, Float: %f, String: %s\n", 
                 @as(c_int, 42), 
                 @as(c_double, 3.14), 
                 "hello");
}

// Creating Zig varargs for C
export fn myVarFunc(count: c_int, ...) c_int {
    var args = @cVaStart();
    defer @cVaEnd(&args);
    
    var sum: c_int = 0;
    var i: c_int = 0;
    while (i < count) : (i += 1) {
        sum += @cVaArg(&args, c_int);
    }
    return sum;
}
```

## Linking C Libraries

```zig
// In build.zig
exe.linkSystemLibrary("c");      // libc
exe.linkSystemLibrary("sqlite3");
exe.linkSystemLibrary("curl");

// Custom library
exe.addLibraryPath(.{ .path = "/usr/local/lib" });
exe.linkSystemLibrary("mylib");

// Include paths
exe.addIncludePath(.{ .path = "/usr/local/include" });

// Frameworks (macOS)
exe.linkFramework("CoreFoundation");
exe.linkFramework("Foundation");
```

## Complete Example: SQLite Wrapper

```zig
const std = @import("std");

const c = @cImport({
    @cInclude("sqlite3.h");
});

pub const Database = struct {
    db: *c.sqlite3,
    
    pub fn open(path: [*:0]const u8) !Database {
        var db: ?*c.sqlite3 = null;
        const result = c.sqlite3_open(path, &db);
        
        if (result != c.SQLITE_OK) {
            return error.DatabaseOpenFailed;
        }
        
        return Database{ .db = db.? };
    }
    
    pub fn close(self: *Database) void {
        _ = c.sqlite3_close(self.db);
    }
    
    pub fn execute(self: *Database, sql: [*:0]const u8) !void {
        const result = c.sqlite3_exec(
            self.db,
            sql,
            null,
            null,
            null,
        );
        
        if (result != c.SQLITE_OK) {
            return error.ExecuteFailed;
        }
    }
};

pub fn main() !void {
    var db = try Database.open("test.db");
    defer db.close();
    
    try db.execute("CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, name TEXT)");
}
```

## C Macros

```zig
// Translate macros
const c = @cImport({
    @cDefine("DEBUG", "1");
    @cDefine("MAX_SIZE", "1024");
    @cDefine("VERSION", "\"1.0.0\"");
    
    @cInclude("myheader.h");
});

// Function-like macros become inline functions
// Object-like macros become constants
const max_size = c.MAX_SIZE;

// Manual definitions for untranslatable macros
const MY_MACRO = 42;
```

## Error Handling Across C Boundary

```zig
// C error codes
extern "c" fn c_operation(value: c_int) c_int;

pub fn operation(value: i32) !void {
    const result = c_operation(@intCast(value));
    
    if (result != 0) {
        return error.OperationFailed;
    }
}

// errno handling
const c = @cImport(@cInclude("errno.h"));

pub fn fileOperation() !void {
    const result = c.some_file_operation();
    
    if (result < 0) {
        const err = c.errno;
        return switch (err) {
            c.ENOENT => error.FileNotFound,
            c.EACCES => error.PermissionDenied,
            else => error.UnknownError,
        };
    }
}
```

## Memory Management with C

```zig
const std = @import("std");

// C allocator (malloc/free)
pub const c_allocator = std.heap.c_allocator;

pub fn example() !void {
    const buffer = try c_allocator.alloc(u8, 1024);
    defer c_allocator.free(buffer);
    
    useCFunction(buffer.ptr);
}

// Wrapping C-allocated memory
const c = @cImport(@cInclude("stdlib.h"));

pub fn allocateFromC() ![]u8 {
    const ptr = c.malloc(100) orelse return error.OutOfMemory;
    const slice: [*]u8 = @ptrCast(@alignCast(ptr));
    return slice[0..100];
}

pub fn freeToC(slice: []u8) void {
    c.free(slice.ptr);
}
```

## Zig as C Compiler

```zig
// In build.zig - compile C code
const c_obj = b.addObject(.{
    .name = "ccode",
    .target = target,
    .optimize = optimize,
});

c_obj.addCSourceFile(.{
    .file = .{ .path = "src/legacy.c" },
    .flags = &[_][]const u8{
        "-std=c99",
        "-Wall",
        "-Wextra",
    },
});

exe.addObject(c_obj);
exe.linkSystemLibrary("c");
```

## Best Practices

```zig
// 1. Use sentinel-terminated strings for C
const c_string: [*:0]const u8 = "hello";

// 2. Use c_int, not i32, for C integers
fn cCompatible(value: c_int) c_int {
    return value * 2;
}

// 3. Wrap C APIs in Zig-friendly interfaces
pub const File = struct {
    handle: *c.FILE,
    
    pub fn open(path: []const u8) !File {
        // Convert, call, wrap
    }
};

// 4. Use extern struct for C structs
const CData = extern struct {
    field1: c_int,
    field2: c_double,
};

// 5. Document ownership
/// Returns C-allocated memory. Caller must call freeToC().
pub fn getCString() ![*:0]u8 {
    // Implementation
}
```
