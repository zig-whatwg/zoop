# Standard Library Reference

## Common Imports

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const testing = std.testing;
```

## Allocators

### Testing Allocator

```zig
test "with testing allocator" {
    const allocator = std.testing.allocator; // Detects leaks
    
    const bytes = try allocator.alloc(u8, 100);
    defer allocator.free(bytes);
    
    try testing.expect(bytes.len == 100);
}
```

### GeneralPurposeAllocator

```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer {
    const leaked = gpa.deinit();
    if (leaked == .leak) {
        std.debug.print("Memory leaked!\n", .{});
    }
}
const allocator = gpa.allocator();
```

### ArenaAllocator

```zig
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
defer arena.deinit(); // Frees everything at once
const allocator = arena.allocator();

const str1 = try allocator.dupe(u8, "hello");
const str2 = try allocator.alloc(u8, 100);
// No individual frees - arena.deinit() handles it
```

### FixedBufferAllocator

```zig
var buffer: [1024]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&buffer);
const allocator = fba.allocator();
// No heap allocation
```

### C Allocator

```zig
const allocator = std.heap.c_allocator;
// Uses malloc/free - works with C libraries
```

## ArrayList

```zig
var list = ArrayList(i32).init(allocator);
defer list.deinit();

// Adding items
try list.append(1);
try list.appendSlice(&[_]i32{ 2, 3, 4 });
try list.insert(0, 0); // Insert at index

// Accessing items
const first = list.items[0];
const last = list.getLast();
const item = list.pop(); // Remove and return last

// Capacity management
try list.ensureTotalCapacity(100);
list.clearRetainingCapacity();
list.clearAndFree();

// Iteration
for (list.items) |item| {
    std.debug.print("{}\n", .{item});
}
```

## HashMap

```zig
var map = std.StringHashMap(i32).init(allocator);
defer map.deinit();

// Adding/updating
try map.put("answer", 42);
try map.putNoClobber("pi", 3); // Error if exists

// Getting values
const value = map.get("answer"); // Returns ?i32
if (map.getPtr("answer")) |ptr| {
    ptr.* = 43; // Modify in place
}

// Removing
const removed = map.remove("answer");
_ = map.fetchRemove("pi"); // Returns KV pair

// Iteration
var iter = map.iterator();
while (iter.next()) |entry| {
    std.debug.print("{s}: {}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
}

// Checking existence
if (map.contains("key")) {
    // Key exists
}
```

## AutoHashMap

```zig
var map = std.AutoHashMap(u32, []const u8).init(allocator);
defer map.deinit();

try map.put(1, "one");
try map.put(2, "two");

const value = map.get(1); // ?[]const u8
```

## String Operations

### String Comparison

```zig
if (std.mem.eql(u8, str1, str2)) {
    // Strings are equal
}
```

### String Searching

```zig
const has_prefix = std.mem.startsWith(u8, string, "prefix");
const has_suffix = std.mem.endsWith(u8, string, "suffix");
const index = std.mem.indexOf(u8, string, "substring"); // ?usize
const last_index = std.mem.lastIndexOf(u8, string, "sub");
```

### String Splitting

```zig
// Split (includes empty)
var iter = std.mem.split(u8, "a,b,c", ",");
while (iter.next()) |part| {
    std.debug.print("{s}\n", .{part});
}

// Tokenize (skips empty)
var tokens = std.mem.tokenize(u8, "  a  b  c  ", " ");
while (tokens.next()) |token| {
    std.debug.print("{s}\n", .{token});
}

// Split sequence
var seq_iter = std.mem.splitSequence(u8, "a::b::c", "::");
while (seq_iter.next()) |part| {
    // Process part
}
```

### String Formatting

```zig
// Allocating format
const message = try std.fmt.allocPrint(
    allocator,
    "Hello, {s}! Count: {}",
    .{ name, count }
);
defer allocator.free(message);

// Stack buffer format
var buf: [100]u8 = undefined;
const result = try std.fmt.bufPrint(
    &buf,
    "Value: {}",
    .{value}
);

// Print to writer
try std.fmt.format(writer, "Value: {}\n", .{value});
```

### Parsing

```zig
// String to int
const num = try std.fmt.parseInt(i32, "42", 10);
const hex = try std.fmt.parseInt(u32, "FF", 16);

// String to float
const float_num = try std.fmt.parseFloat(f64, "3.14");

// Number to string
var buf: [20]u8 = undefined;
const num_str = try std.fmt.bufPrint(&buf, "{}", .{42});
```

## File I/O

### Reading Files

```zig
// Read entire file
const file_contents = try std.fs.cwd().readFileAlloc(
    allocator,
    "input.txt",
    1024 * 1024, // max size
);
defer allocator.free(file_contents);

// Read file into buffer
var buffer: [1024]u8 = undefined;
const file = try std.fs.cwd().openFile("input.txt", .{});
defer file.close();

const bytes_read = try file.readAll(&buffer);
```

### Writing Files

```zig
// Write entire file
try std.fs.cwd().writeFile("output.txt", "Hello, World!");

// Write with file handle
const file = try std.fs.cwd().createFile("output.txt", .{});
defer file.close();

try file.writeAll("Hello, World!\n");

// Buffered writer
var buf_writer = std.io.bufferedWriter(file.writer());
const writer = buf_writer.writer();

try writer.writeAll("Line 1\n");
try writer.print("Value: {}\n", .{42});

try buf_writer.flush();
```

### Directory Operations

```zig
// Create directory
try std.fs.cwd().makeDir("new_dir");
try std.fs.cwd().makePath("path/to/dir"); // Create parents

// Delete directory
try std.fs.cwd().deleteDir("old_dir");
try std.fs.cwd().deleteTree("path/to/dir"); // Recursive

// Iterate directory
var dir = try std.fs.cwd().openDir(".", .{ .iterate = true });
defer dir.close();

var iter = dir.iterate();
while (try iter.next()) |entry| {
    std.debug.print("{s} ({s})\n", .{ entry.name, @tagName(entry.kind) });
}
```

## JSON

### Parsing JSON

```zig
const User = struct {
    name: []const u8,
    age: u32,
    email: ?[]const u8 = null,
};

const json_string = 
    \\{"name": "Alice", "age": 30}
;

const parsed = try std.json.parseFromSlice(
    User,
    allocator,
    json_string,
    .{},
);
defer parsed.deinit();

const user = parsed.value;
std.debug.print("Name: {s}, Age: {}\n", .{ user.name, user.age });
```

### Stringifying JSON

```zig
const user = User{
    .name = "Bob",
    .age = 25,
};

var json_string = std.ArrayList(u8).init(allocator);
defer json_string.deinit();

try std.json.stringify(user, .{}, json_string.writer());
std.debug.print("{s}\n", .{json_string.items});
```

## Process and System

### Command Line Arguments

```zig
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    for (args, 0..) |arg, i| {
        std.debug.print("arg[{}]: {s}\n", .{ i, arg });
    }
}
```

### Environment Variables

```zig
// Get env var
const path = std.process.getEnvVarOwned(allocator, "PATH") catch |err| {
    std.debug.print("PATH not set: {}\n", .{err});
    return;
};
defer allocator.free(path);

// Set env var (Unix only)
try std.process.setEnvVar("MY_VAR", "value");

// Unset env var
try std.process.unsetEnvVar("MY_VAR");
```

### Running Child Processes

```zig
const result = try std.process.Child.run(.{
    .allocator = allocator,
    .argv = &[_][]const u8{ "ls", "-la" },
});
defer allocator.free(result.stdout);
defer allocator.free(result.stderr);

std.debug.print("stdout:\n{s}\n", .{result.stdout});
std.debug.print("stderr:\n{s}\n", .{result.stderr});

if (result.term.Exited != 0) {
    return error.CommandFailed;
}
```

## Time

```zig
// Current timestamp
const timestamp = std.time.timestamp(); // seconds since epoch
const millis = std.time.milliTimestamp();
const nanos = std.time.nanoTimestamp();

// Sleep
std.time.sleep(1 * std.time.ns_per_s); // 1 second

// Timing code
const start = std.time.nanoTimestamp();
// ... code to time ...
const end = std.time.nanoTimestamp();
const duration = end - start;
std.debug.print("Took {} ns\n", .{duration});
```

## Random

```zig
var prng = std.Random.DefaultPrng.init(blk: {
    var seed: u64 = undefined;
    try std.posix.getrandom(std.mem.asBytes(&seed));
    break :blk seed;
});
const random = prng.random();

const rand_int = random.int(u32);
const rand_range = random.intRangeAtMost(u32, 1, 100);
const rand_float = random.float(f64);
const rand_bool = random.boolean();

// Shuffle slice
var items = [_]u32{ 1, 2, 3, 4, 5 };
random.shuffle(u32, &items);
```

## Testing Utilities

```zig
const testing = std.testing;

test "expectations" {
    try testing.expect(true);
    try testing.expectEqual(@as(i32, 42), 42);
    try testing.expectEqualStrings("hello", "hello");
    try testing.expectEqualSlices(u8, &[_]u8{ 1, 2 }, &[_]u8{ 1, 2 });
    try testing.expectError(error.Fail, failingFunc());
}

test "float approximation" {
    try testing.expectApproxEqAbs(
        @as(f64, 0.1) + 0.2,
        @as(f64, 0.3),
        0.0001,
    );
}

test "allocations" {
    const allocator = testing.allocator;
    
    const bytes = try allocator.alloc(u8, 10);
    defer allocator.free(bytes);
    
    try testing.expect(bytes.len == 10);
}
```

## Memory Operations

```zig
// Copy memory
const src = [_]u8{ 1, 2, 3, 4 };
var dst: [4]u8 = undefined;
@memcpy(&dst, &src);

// Set memory
var buffer: [100]u8 = undefined;
@memset(&buffer, 0);

// Compare memory
if (std.mem.eql(u8, &buffer1, &buffer2)) {
    // Equal
}

// Duplicate slice
const original = [_]u8{ 1, 2, 3 };
const copy = try allocator.dupe(u8, &original);
defer allocator.free(copy);

// Zero memory (security)
std.crypto.utils.secureZero(u8, &sensitive_data);
```

## Bit Manipulation

```zig
// Count bits
const set_bits = @popCount(@as(u32, 0b1011)); // 3

// Leading/trailing zeros
const leading = @clz(@as(u32, 0b0001_0000)); // 27
const trailing = @ctz(@as(u32, 0b0001_0000)); // 4

// Byte swap
const swapped = @byteSwap(@as(u32, 0x12345678)); // 0x78563412

// Bit cast
const float_bits = @as(u32, @bitCast(@as(f32, 3.14)));
```

## Logging

```zig
const std = @import("std");
const log = std.log;

pub fn main() void {
    log.debug("Debug message", .{});
    log.info("Info: {}", .{42});
    log.warn("Warning!", .{});
    log.err("Error: {s}", .{"failed"});
}

// Custom logging
pub const std_options = struct {
    pub const log_level = .debug;
    
    pub fn logFn(
        comptime level: std.log.Level,
        comptime scope: @Type(.EnumLiteral),
        comptime format: []const u8,
        args: anytype,
    ) void {
        const prefix = "[" ++ @tagName(level) ++ "] ";
        std.debug.print(prefix ++ format ++ "\n", args);
    }
};
```
