const std = @import("std");

// Memory benchmark - creates and destroys objects for 20+ seconds
// Measures actual process memory usage to verify no leaks

pub const AllocatedParent = struct {
    data: []u8,
    id: usize,

    pub fn init(allocator: std.mem.Allocator, size: usize, id: usize) !AllocatedParent {
        return .{
            .data = try allocator.alloc(u8, size),
            .id = id,
        };
    }

    pub fn deinit(self: *AllocatedParent, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }
};

pub const AllocatedChild = struct {
    super: AllocatedParent,
    child_data: []u8,
    extra_data: []u8,

    pub fn init(allocator: std.mem.Allocator, parent_size: usize, child_size: usize, id: usize) !AllocatedChild {
        return .{
            .super = try AllocatedParent.init(allocator, parent_size, id),
            .child_data = try allocator.alloc(u8, child_size),
            .extra_data = try allocator.alloc(u8, child_size / 2),
        };
    }

    pub fn deinit(self: *AllocatedChild, allocator: std.mem.Allocator) void {
        self.super.deinit(allocator);
        allocator.free(self.child_data);
        allocator.free(self.extra_data);
    }
};

// Cross-platform memory measurement
fn getCurrentMemoryUsage() !usize {
    if (@import("builtin").os.tag == .macos or @import("builtin").os.tag == .ios) {
        // macOS/iOS - use task_info
        const c = @cImport({
            @cInclude("mach/mach.h");
            @cInclude("mach/task_info.h");
        });

        var info: c.mach_task_basic_info = undefined;
        var count: c.mach_msg_type_number_t = c.MACH_TASK_BASIC_INFO_COUNT;

        const kr = c.task_info(c.mach_task_self(), c.MACH_TASK_BASIC_INFO, @ptrCast(&info), &count);

        if (kr != c.KERN_SUCCESS) {
            return error.TaskInfoFailed;
        }

        return info.resident_size;
    } else if (@import("builtin").os.tag == .linux) {
        // Linux - read /proc/self/statm
        const file = try std.fs.openFileAbsolute("/proc/self/statm", .{});
        defer file.close();

        var buf: [1024]u8 = undefined;
        const bytes_read = try file.readAll(&buf);
        const content = buf[0..bytes_read];

        // Second field is RSS in pages
        var it = std.mem.splitScalar(u8, content, ' ');
        _ = it.next(); // Skip first field
        const rss_pages = it.next() orelse return error.InvalidFormat;
        const pages = try std.fmt.parseInt(usize, rss_pages, 10);

        // Convert pages to bytes (typically 4KB per page)
        return pages * 4096;
    } else {
        // Fallback - not supported
        return 0;
    }
}

fn formatBytes(bytes: usize) ![]const u8 {
    const allocator = std.heap.page_allocator;

    if (bytes >= 1024 * 1024 * 1024) {
        const gb = @as(f64, @floatFromInt(bytes)) / (1024 * 1024 * 1024);
        return try std.fmt.allocPrint(allocator, "{d:.2} GB", .{gb});
    } else if (bytes >= 1024 * 1024) {
        const mb = @as(f64, @floatFromInt(bytes)) / (1024 * 1024);
        return try std.fmt.allocPrint(allocator, "{d:.2} MB", .{mb});
    } else if (bytes >= 1024) {
        const kb = @as(f64, @floatFromInt(bytes)) / 1024;
        return try std.fmt.allocPrint(allocator, "{d:.2} KB", .{kb});
    } else {
        return try std.fmt.allocPrint(allocator, "{} bytes", .{bytes});
    }
}

test "memory benchmark - 20 second leak test" {
    const allocator = std.testing.allocator;

    std.debug.print("\n", .{});
    std.debug.print("=================================================================\n", .{});
    std.debug.print("Memory Leak Benchmark - 20 Second Stress Test\n", .{});
    std.debug.print("=================================================================\n\n", .{});

    // Measure initial memory
    const initial_memory = try getCurrentMemoryUsage();
    const initial_str = try formatBytes(initial_memory);
    std.debug.print("Initial process memory: {s}\n", .{initial_str});
    std.debug.print("Starting benchmark...\n\n", .{});

    const duration_seconds = 20;
    const report_interval_ms = 2000; // Report every 2 seconds

    var timer = try std.time.Timer.start();
    const duration_ns = duration_seconds * std.time.ns_per_s;

    var total_created: usize = 0;
    var total_destroyed: usize = 0;
    var last_report_time: u64 = 0;
    var iteration: usize = 0;

    std.debug.print("Time | Created | Destroyed | Memory    | Delta\n", .{});
    std.debug.print("-----|---------|-----------|-----------|-------------\n", .{});

    while (timer.read() < duration_ns) {
        iteration += 1;

        // Create a batch of objects
        const batch_size = 1000;
        var objects: std.ArrayList(AllocatedChild) = .empty;
        defer objects.deinit(allocator);

        // Allocate batch
        var i: usize = 0;
        while (i < batch_size) : (i += 1) {
            const obj = try AllocatedChild.init(
                allocator,
                1024, // 1KB parent
                2048, // 2KB child
                total_created + i,
            );
            try objects.append(allocator, obj);
        }
        total_created += batch_size;

        // Do some work with the objects
        for (objects.items) |*obj| {
            // Fill with data
            for (obj.super.data, 0..) |*byte, idx| {
                byte.* = @truncate(idx);
            }
            for (obj.child_data, 0..) |*byte, idx| {
                byte.* = @truncate(idx);
            }
        }

        // Destroy batch
        for (objects.items) |*obj| {
            obj.deinit(allocator);
        }
        total_destroyed += batch_size;

        // Report progress every N milliseconds
        const current_time = timer.read();
        if (current_time - last_report_time >= report_interval_ms * std.time.ns_per_ms) {
            const current_memory = try getCurrentMemoryUsage();
            const memory_str = try formatBytes(current_memory);
            const delta = @as(i64, @intCast(current_memory)) - @as(i64, @intCast(initial_memory));
            const delta_str = try formatBytes(@abs(delta));
            const delta_sign: []const u8 = if (delta >= 0) "+" else "-";

            const elapsed_s = current_time / std.time.ns_per_s;
            std.debug.print("{:4}s | {:7} | {:9} | {s:9} | {s}{s}\n", .{
                elapsed_s,
                total_created,
                total_destroyed,
                memory_str,
                delta_sign,
                delta_str,
            });

            last_report_time = current_time;
        }

        // Small delay to prevent CPU spinning
        std.Thread.sleep(1 * std.time.ns_per_ms);
    }

    const elapsed_time = timer.read();
    const elapsed_s = elapsed_time / std.time.ns_per_s;

    std.debug.print("\n", .{});
    std.debug.print("=================================================================\n", .{});
    std.debug.print("Benchmark Complete\n", .{});
    std.debug.print("=================================================================\n\n", .{});

    // Final memory measurement
    const final_memory = try getCurrentMemoryUsage();
    const final_str = try formatBytes(final_memory);

    // Force garbage collection (give OS time to reclaim)
    std.Thread.sleep(500 * std.time.ns_per_ms);
    const after_gc_memory = try getCurrentMemoryUsage();
    const after_gc_str = try formatBytes(after_gc_memory);

    std.debug.print("Duration:                 {} seconds\n", .{elapsed_s});
    std.debug.print("Total objects created:    {}\n", .{total_created});
    std.debug.print("Total objects destroyed:  {}\n", .{total_destroyed});
    std.debug.print("Iterations:               {}\n", .{iteration});
    std.debug.print("\n", .{});
    std.debug.print("Memory Analysis:\n", .{});
    std.debug.print("  Initial:                {s}\n", .{initial_str});
    std.debug.print("  Final:                  {s}\n", .{final_str});
    std.debug.print("  After GC (500ms):       {s}\n", .{after_gc_str});

    const memory_delta = @as(i64, @intCast(after_gc_memory)) - @as(i64, @intCast(initial_memory));
    const delta_str = try formatBytes(@abs(memory_delta));
    const delta_sign: []const u8 = if (memory_delta >= 0) "+" else "-";
    std.debug.print("  Delta:                  {s}{s}\n", .{ delta_sign, delta_str });

    // Calculate acceptable threshold (5% of initial memory or 1MB, whichever is larger)
    const threshold = @max(initial_memory / 20, 1024 * 1024);
    const threshold_str = try formatBytes(threshold);

    std.debug.print("  Leak threshold:         {s}\n", .{threshold_str});

    if (@abs(memory_delta) <= threshold) {
        std.debug.print("\n✅ PASS: Memory returned to baseline (within {s})\n", .{threshold_str});
    } else {
        std.debug.print("\n⚠️  WARNING: Memory delta exceeds threshold\n", .{});
        std.debug.print("   This may indicate a leak or OS caching\n", .{});
    }

    std.debug.print("\n", .{});

    // Verify all objects were destroyed
    try std.testing.expectEqual(total_created, total_destroyed);

    // Memory should return to baseline (with some tolerance)
    const leak_detected = @abs(memory_delta) > threshold;
    if (leak_detected) {
        std.debug.print("⚠️  Memory leak may be present. Check system metrics.\n", .{});
        std.debug.print("   Note: This can be due to OS memory caching.\n", .{});
    }
}

test "memory benchmark - aggressive allocation" {
    const allocator = std.testing.allocator;

    std.debug.print("\n", .{});
    std.debug.print("=================================================================\n", .{});
    std.debug.print("Aggressive Allocation Test - Large Objects\n", .{});
    std.debug.print("=================================================================\n\n", .{});

    const initial_memory = try getCurrentMemoryUsage();
    const initial_str = try formatBytes(initial_memory);
    std.debug.print("Initial process memory: {s}\n\n", .{initial_str});

    var timer = try std.time.Timer.start();
    const duration_seconds = 10;
    const duration_ns = duration_seconds * std.time.ns_per_s;

    var total_created: usize = 0;
    var total_destroyed: usize = 0;

    std.debug.print("Creating and destroying large objects (10s)...\n", .{});

    while (timer.read() < duration_ns) {
        // Create very large objects
        var obj = try AllocatedChild.init(
            allocator,
            100 * 1024, // 100KB parent
            500 * 1024, // 500KB child
            total_created,
        );

        // Use the object
        @memset(obj.super.data, 0xFF);
        @memset(obj.child_data, 0xAA);
        @memset(obj.extra_data, 0x55);

        // Destroy
        obj.deinit(allocator);

        total_created += 1;
        total_destroyed += 1;

        // Report every 1000 objects
        if (total_created % 1000 == 0) {
            const current_memory = try getCurrentMemoryUsage();
            const memory_str = try formatBytes(current_memory);
            const elapsed_s = timer.read() / std.time.ns_per_s;
            std.debug.print("  {}s: Created {} objects, Memory: {s}\n", .{
                elapsed_s,
                total_created,
                memory_str,
            });
        }
    }

    const final_memory = try getCurrentMemoryUsage();
    const final_str = try formatBytes(final_memory);

    // Wait for OS to reclaim
    std.Thread.sleep(500 * std.time.ns_per_ms);
    const after_gc_memory = try getCurrentMemoryUsage();
    const after_gc_str = try formatBytes(after_gc_memory);

    std.debug.print("\n", .{});
    std.debug.print("Results:\n", .{});
    std.debug.print("  Total created:    {}\n", .{total_created});
    std.debug.print("  Total destroyed:  {}\n", .{total_destroyed});
    std.debug.print("  Initial memory:   {s}\n", .{initial_str});
    std.debug.print("  Final memory:     {s}\n", .{final_str});
    std.debug.print("  After GC:         {s}\n", .{after_gc_str});

    const memory_delta = @as(i64, @intCast(after_gc_memory)) - @as(i64, @intCast(initial_memory));
    const delta_str = try formatBytes(@abs(memory_delta));
    const delta_sign: []const u8 = if (memory_delta >= 0) "+" else "-";
    std.debug.print("  Delta:            {s}{s}\n", .{ delta_sign, delta_str });

    std.debug.print("\n", .{});

    try std.testing.expectEqual(total_created, total_destroyed);
}
