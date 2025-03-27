const std = @import("std");

fn standardPlatformOption(b: *std.Build, target: std.Build.ResolvedTarget) []const u8 {
    if (target.result.os.tag == .freestanding) {
        return b.option([]const u8, "platform", "The freestanding platform") orelse @panic("Missing platform option");
    }
    return @tagName(target.result.os.tag);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const platform = standardPlatformOption(b, target);
    const use_llvm = b.option(bool, "use-llvm", "Use LLVM or Zig's built in codegen");

    const options = b.addOptions();
    options.addOption([]const u8, "platform", platform);

    const kernel_exec = b.addExecutable(.{
        .name = "zenith",
        .linkage = .static,
        .use_llvm = use_llvm,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("kernel/main.zig"),
            .code_model = if (target.result.os.tag == .freestanding and target.result.cpu.arch.isX86()) .kernel else .default,
            .imports = &.{
                .{
                    .name = "options",
                    .module = options.createModule(),
                },
            },
        }),
    });

    if (target.result.os.tag == .freestanding) {
        kernel_exec.setLinkerScript(b.path(b.pathJoin(&.{
            "kernel",
            "arch",
            @tagName(target.result.cpu.arch),
            "platforms",
            platform,
            "linker.ld",
        })));

        kernel_exec.link_gc_sections = false;
    }

    b.installArtifact(kernel_exec);
}
