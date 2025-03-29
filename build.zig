const std = @import("std");

fn standardTargetOptions(b: *std.Build, options: std.Build.StandardTargetOptionsArgs) std.Build.ResolvedTarget {
    const target = b.standardTargetOptions(options);

    const is_baseline = target.result.cpu.model == std.Target.Cpu.baseline(target.result.cpu.arch, target.result.os).model;
    const is_generic = target.result.cpu.model == std.Target.Cpu.Model.generic(target.result.cpu.arch);
    if (target.result.os.tag == .freestanding and (!is_baseline or !is_generic)) {
        var query: std.Target.Query = .{
            .cpu_arch = target.result.cpu.arch,
            .os_tag = .freestanding,
            .abi = target.result.abi,
        };

        switch (target.result.cpu.arch) {
            .x86, .x86_64 => {
                const Target = std.Target.x86;

                query.cpu_features_add = Target.featureSet(&.{ .popcnt, .soft_float });
                query.cpu_features_sub = Target.featureSet(&.{ .avx, .avx2, .sse, .sse2, .mmx });
            },
            .aarch64 => {
                const Target = std.Target.aarch64;

                query.cpu_features_add = Target.featureSet(&.{});
                query.cpu_features_sub = Target.featureSet(&.{ .fp_armv8, .crypto, .neon });
            },
            else => {},
        }

        return b.resolveTargetQuery(query);
    }

    return target;
}

fn standardPlatformOption(b: *std.Build, target: std.Build.ResolvedTarget) []const u8 {
    if (target.result.os.tag == .freestanding) {
        return b.option([]const u8, "platform", "The freestanding platform") orelse @panic("Missing platform option");
    }
    return @tagName(target.result.os.tag);
}

pub fn build(b: *std.Build) void {
    const target = standardTargetOptions(b, .{});
    const optimize = b.standardOptimizeOption(.{});
    const platform = standardPlatformOption(b, target);
    const use_llvm = b.option(bool, "use-llvm", "Use LLVM or Zig's built in codegen");

    const options = b.addOptions();
    options.addOption([]const u8, "platform", platform);

    const limine = b.dependency("limine", .{
        .api_revision = 3,
    });

    const kernel_exec = b.addExecutable(.{
        .name = "zenith",
        .linkage = .static,
        .use_llvm = use_llvm,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("kernel/main.zig"),
            .imports = &.{
                .{
                    .name = "options",
                    .module = options.createModule(),
                },
                .{
                    .name = "limine",
                    .module = limine.module("limine"),
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

        kernel_exec.name_only_filename = kernel_exec.name_only_filename;
        kernel_exec.out_lib_filename = kernel_exec.out_filename;

        kernel_exec.link_gc_sections = false;

        if (target.result.cpu.arch.isX86()) {
            kernel_exec.root_module.red_zone = false;
            kernel_exec.root_module.code_model = .kernel;
        }
    }

    if (std.mem.count(u8, platform, "limine") > 0) {
        b.installFile("config/limine.conf", "boot/limine/limine.conf");
    }

    b.getInstallStep().dependOn(&b.addInstallArtifact(kernel_exec, .{
        .dest_dir = switch (target.result.os.tag) {
            .freestanding => .{
                .override = .{
                    .custom = "boot",
                },
            },
            .uefi => .{
                .override = .{
                    .custom = "EFI/BOOT",
                },
            },
            else => .default,
        },
    }).step);
}
