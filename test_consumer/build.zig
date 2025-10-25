const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Run code generation FIRST
    const zoop_dep = b.dependency("zoop", .{
        .target = target,
        .optimize = optimize,
    });
    
    const codegen_exe = zoop_dep.artifact("zoop-codegen");
    const gen_cmd = b.addRunArtifact(codegen_exe);
    gen_cmd.addArgs(&.{
        "--source-dir", "src",
        "--output-dir", "src_generated",
        "--method-prefix", "call_",
        "--getter-prefix", "get_",
        "--setter-prefix", "set_",
    });

    // Create executable from GENERATED code
    const exe = b.addExecutable(.{
        .name = "test_consumer",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src_generated/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    
    const zoop_module = zoop_dep.module("zoop");
    exe.root_module.addImport("zoop", zoop_module);
    
    // Make exe depend on code generation
    exe.step.dependOn(&gen_cmd.step);

    b.installArtifact(exe);
    
    // Add run step
    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the test consumer");
    run_step.dependOn(&run_cmd.step);
}
