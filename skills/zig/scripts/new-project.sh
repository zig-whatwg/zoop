#!/bin/bash
set -e

if [ -z "$1" ]; then
    echo "Usage: ./new-project.sh <project-name>"
    echo "Creates a new Zig project with standard structure"
    exit 1
fi

PROJECT_NAME="$1"

echo "Creating Zig project: $PROJECT_NAME"

mkdir -p "$PROJECT_NAME/src"
cd "$PROJECT_NAME"

cat > build.zig << 'EOF'
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "PROJECT_NAME",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    b.installArtifact(exe);
    
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    
    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_cmd.step);
    
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
EOF

sed -i.bak "s/PROJECT_NAME/$PROJECT_NAME/g" build.zig && rm build.zig.bak

cat > src/main.zig << 'EOF'
const std = @import("std");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Hello, Zig!\n", .{});
}

test "basic test" {
    const testing = std.testing;
    try testing.expect(2 + 2 == 4);
}
EOF

cat > .gitignore << 'EOF'
zig-cache/
zig-out/
.zig-cache/
EOF

cat > README.md << EOF
# $PROJECT_NAME

A Zig project.

## Build

\`\`\`bash
zig build
\`\`\`

## Run

\`\`\`bash
zig build run
\`\`\`

## Test

\`\`\`bash
zig build test
\`\`\`
EOF

echo "✓ Created project structure:"
echo "  $PROJECT_NAME/"
echo "  ├── build.zig"
echo "  ├── src/"
echo "  │   └── main.zig"
echo "  ├── .gitignore"
echo "  └── README.md"
echo ""
echo "Get started:"
echo "  cd $PROJECT_NAME"
echo "  zig build run"
