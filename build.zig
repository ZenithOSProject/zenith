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

fn standardPlatformOption(b: *std.Build, target: std.Build.ResolvedTarget) ?[]const u8 {
    if (target.result.os.tag == .freestanding) {
        return b.option([]const u8, "platform", "The freestanding platform");
    }
    return @tagName(target.result.os.tag);
}

fn qemuBinary(b: *std.Build, target: std.Target) []const u8 {
    return b.fmt("qemu-system-{s}", .{switch (target.cpu.arch) {
        .x86 => "i386",
        else => @tagName(target.cpu.arch),
    }});
}

pub fn build(b: *std.Build) void {
    const target = standardTargetOptions(b, .{});
    const optimize = b.standardOptimizeOption(.{});
    const use_llvm = b.option(bool, "use-llvm", "Use LLVM or Zig's built in codegen");

    const module = b.addModule("zenith", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("lib/zenith.zig"),
    });

    const step_test = b.step("test", "Run unit tests");

    if (target.result.os.tag != .freestanding) {
        const module_tests = b.addTest(.{
            .root_module = module,
        });

        const run_module_tests = b.addRunArtifact(module_tests);
        step_test.dependOn(&run_module_tests.step);

        b.getInstallStep().dependOn(&b.addInstallDirectory(.{
            .source_dir = module_tests.getEmittedDocs(),
            .install_dir = .prefix,
            .install_subdir = "docs/zenith",
        }).step);
    }

    if (standardPlatformOption(b, target)) |platform| {
        const options = b.addOptions();
        options.addOption([]const u8, "platform", platform);

        const limine = b.dependency("limine", .{
            .api_revision = 3,
        });

        const kernel_module = b.createModule(.{
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
                .{
                    .name = "zenith",
                    .module = module,
                },
            },
        });

        const kernel_exec = b.addExecutable(.{
            .name = "zenith",
            .linkage = .static,
            .use_llvm = use_llvm,
            .root_module = kernel_module,
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

            if (target.result.cpu.arch.isX86()) {
                kernel_module.red_zone = false;
                kernel_module.code_model = .kernel;
            }

            const kernel_test = b.addTest(.{
                .root_module = kernel_module,
                .test_runner = .{
                    .path = b.path("kernel/test_main.zig"),
                    .mode = .simple,
                },
            });

            kernel_test.link_gc_sections = false;
            kernel_test.setLinkerScript(kernel_exec.linker_script orelse unreachable);

            b.getInstallStep().dependOn(&b.addInstallDirectory(.{
                .source_dir = kernel_test.getEmittedDocs(),
                .install_dir = .prefix,
                .install_subdir = "docs/zenith",
            }).step);

            const run_kernel_test = b.addSystemCommand(&.{
                b.findProgram(&.{
                    qemuBinary(b, target.result),
                }, &.{}) catch |err| std.debug.panic("Cannot find QEMU binary \"{s}\": {s}", .{ qemuBinary(b, target.result), @errorName(err) }),
            });

            run_kernel_test.addArgs(&.{
                "-nographic",
                "-display",
                "none",
                "-monitor",
                "none",
                "-serial",
                "stdio",
            });

            switch (target.result.cpu.arch) {
                .aarch64 => {
                    if (std.mem.eql(u8, platform, "qemu-virt")) {
                        run_kernel_test.addArgs(&.{
                            "-machine",
                            "virt",
                            "-cpu",
                            "cortex-a57",
                            "-kernel",
                        });

                        run_kernel_test.addFileArg(kernel_test.getEmittedBin());
                    }
                },
                .x86 => {
                    if (std.mem.eql(u8, platform, "pc-multiboot")) {
                        run_kernel_test.addArg("-kernel");
                        run_kernel_test.addFileArg(kernel_test.getEmittedBin());
                    }
                },
                else => {},
            }

            step_test.dependOn(&run_kernel_test.step);
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
}
