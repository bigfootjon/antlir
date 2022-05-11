load("//antlir/bzl:shape.bzl", "shape")
load("//metalos:defs.bzl", "rust_binary")
load("//metalos:metalos_tests.shape.bzl", "container_unittest_opts_t", "unittest_opts_t")

def metalctl(name, rustc_flags = None, extra_deps = [], extra_srcs = [], **kwargs):
    srcs = native.glob(["src/*.rs"]) + extra_srcs

    # WARNING: these common_deps are included in both the initrd and rootfs builds
    # of metalctl. The size of the initrd is constrained and must remain small if we
    # ever want to pxe-boot it directly. Be prepared to justify any size increases
    # brought in by large dependencies.
    deps = [
        "//metalos/host_configs/evalctx:evalctx",
        "//metalos/host_configs/rust:metalos_host_configs",
        "//metalos/lib/btrfs:btrfs",
        "//metalos/lib/kernel_cmdline:kernel_cmdline",
        "//metalos/lib/get_host_config:get_host_config",
        "//metalos/lib/expand_partition:expand_partition",
        "//metalos/lib/find_root_disk:find_root_disk",
        "//metalos/lib/apply_disk_image:apply_disk_image",
        # Apparently dep ordering matters to the linker.  If the `blkid` dep
        # is moved _above_ the `find_root_disk` dep the linker will complain
        # about duplicate symbols contained in both:
        # `util-linux/lib/libblkid.a`
        # and
        # `systemd/lib/libudev.a`
        # when this is compiled statically, as is done for the `metalctl-initrd`
        # target.  So, tl;dr is that this `blkid` dep nees to be underneath
        # `find_root_disk`...
        "//metalos/lib/blkid:blkid",
        "//metalos/lib/metalos_paths:metalos_paths",
        "//metalos/lib/mount:metalos_mount",
        "//metalos/lib/net_utils:net_utils",
        "//metalos/lib/package_download:package_download",
        "//metalos/lib/send_events:send_events",
        "//metalos/lib/systemd:systemd",
        "//metalos/host_configs/lifecycle:lifecycle",
        "anyhow",  # ~9.5k, very helpful for error handling
        "fbthrift",
        "nix",  # ~5k: access to syscalls (mount, etc)
        "libc",
        "structopt",  # ~300k, but makes iterating development much easier
        # all the slog crates together add about 50k
        "slog",
        "slog-async",
        "slog-term",
        "slog_glog_fmt",
        "toml",  # load config files
        "serde",  # load config files
        "serde_json",
        "maplit",  # Should be macros only so little to no difference in output binary
        "shlex",
        "strum",
        "strum_macros",  # I <3 zero cost abstractions!
        # Needed for HTTPS requests to download images
        "url",
        "bytes",
        "futures",
        "futures-core",
        "futures-util",
        "reqwest",
        "tokio",  # async runtime for http client
        "zstd",
    ] + extra_deps

    rustc_flags = rustc_flags or []
    rustc_flags.append("--cfg=blkid")

    # metalctl is split into two binary targets, so that code that requires
    # features only found in the rootfs, or larger dependencies can be excluded
    # from the initrd.

    rust_binary(
        name = name,
        srcs = srcs,
        crate_root = "src/metalctl.rs",
        deps = deps,
        test_deps = [
            "http",
            "mockall",
            "tempfile",
            "//metalos/lib/http_test:http_test",
            "//metalos/host_configs/tests:example_host_for_tests",
        ],
        test_srcs = native.glob(["tests/**/*.rs"]),
        unittest_opts = shape.new(
            unittest_opts_t,
            container = shape.new(
                container_unittest_opts_t,
                boot = True,
            ),
        ),
        unittests = ["plain", "container", "vm"],
        rustc_flags = rustc_flags,
        # TODO(T113359879) this can be removed when there are no more split
        # builds of metalctl
        __metalctl_only_allow_unused_deps = True,
        **kwargs
    )
