#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""
This is normally invoked by the `image_layer` Buck macro converter.

This compiler builds a btrfs subvolume in
  <--subvolumes-dir>/<--subvolume-rel-path>

To do so, it parses `--child-feature-json` and the `--child-dependencies`
that referred therein, creates `ImageItems`, sorts them in dependency order,
and invokes `.build()` to apply each item to actually construct the subvol.
"""

import argparse
import concurrent.futures
import cProfile
import os
import pwd
import stat
import sys
from contextlib import ExitStack, nullcontext
from subprocess import CalledProcessError
from typing import Iterator, List

from antlir.bzl.constants import flavor_config_t
from antlir.bzl_const import hostname_for_compiler_in_ba
from antlir.cli import add_targets_and_outputs_arg
from antlir.common import not_none
from antlir.compiler.items.common import LayerOpts
from antlir.compiler.items.phases_provide import PhasesProvideItem
from antlir.compiler.items_for_features import gen_items_for_features
from antlir.config import repo_config
from antlir.find_built_subvol import find_built_subvol
from antlir.fs_utils import META_FLAVOR_FILE, Path
from antlir.nspawn_in_subvol.args import (
    PopenArgs,
    new_nspawn_opts,
    NspawnPluginArgs,
)
from antlir.nspawn_in_subvol.nspawn import run_nspawn
from antlir.nspawn_in_subvol.plugins.rpm import rpm_nspawn_plugins
from antlir.rpm.yum_dnf_conf import YumDnf
from antlir.subvol_utils import Subvol

from .dep_graph import DependencyGraph, ImageItem
from .subvolume_on_disk import SubvolumeOnDisk
from .user_error import UserError


def parse_args(args) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument(
        "--subvolumes-dir",
        required=True,
        type=Path.from_argparse,
        help="A directory on a btrfs volume to store the compiled subvolume "
        "representing the new layer",
    )
    # We separate this from `--subvolumes-dir` in order to help keep our
    # JSON output ignorant of the absolute path of the repo.
    parser.add_argument(
        "--subvolume-rel-path",
        required=True,
        type=Path.from_argparse,
        help="Path underneath --subvolumes-dir where we should create "
        "the subvolume. Note that all path components but the basename "
        "should already exist.",
    )
    parser.add_argument(
        "--flavor-config",
        type=flavor_config_t.parse_raw,
        help="The serialized config for the flavor. This contains "
        "information about the build appliance and rpm installer.",
    )
    parser.add_argument(
        "--artifacts-may-require-repo",
        action="store_true",
        help='Buck @mode/dev produces "in-place" build artifacts that are '
        "not truly standalone. It is important to be able to execute "
        "code from images built in this mode to support rapid "
        'development and debugging, even though it is not a "true" '
        "self-contained image. To allow execution of in-place binaries, "
        "antlir runtimes will automatically mount the repo into any "
        "`--artifacts-may-require-repo` image at runtime (e.g. when "
        "running image unit-tests, when using `=container` or `=systemd` "
        "targets, when using the image as a build appliance).",
    )
    parser.add_argument(
        "--child-layer-target",
        required=True,
        help="The name of the Buck target describing the layer being built",
    )
    parser.add_argument(
        "--child-feature-json",
        action="append",
        default=[],
        help="The path of the JSON output of any `feature`s that are"
        "directly included by the layer being built",
    )
    parser.add_argument("--debug", action="store_true", help="Log more")
    parser.add_argument(
        "--allowed-host-mount-target",
        action="append",
        default=[],
        help="Target name that is allowed to contain host mounts used as "
        "build_sources.  Can be specified more than once.",
    )
    parser.add_argument(
        "--version-set-override",
        help="Path to a file containing TAB-separated ENVRAs, one per line."
        "Also refer to `build_opts.bzl`.",
    )
    parser.add_argument(
        "--parent-layer",
        help="The directory of the buck image output of the parent layer. "
        "We will read the flavor from the parent layer to deduce the flavor "
        "of the child layer",
    )
    parser.add_argument(
        "--profile",
        default=os.environ.get("ANTLIR_PROFILE"),
        dest="profile_dir",
        type=Path.from_argparse,
        help="Profile this image build and write pstats files into the given directory.",
    )
    parser.add_argument(
        "--compiler-binary",
        required=True,
        help="The path to the compiler binary being invoked currently. "
        "It is used to re-invoke the compiler inside the BA container as root.",
    )
    parser.add_argument(
        "--is-nested",
        action="store_true",
        help="Indicates whether the compiler binary is being run nested inside "
        "a BA container.",
    )
    parser.add_argument(
        "--internal-only-is-genrule-layer",
        action="store_true",
        help="Indicates whether the layer being compiled is a genrule layer. "
        "This is a temporary crutch to avoid running the compiler inside a BA "
        "container when building genrule layers. This should be removed in "
        "the future.",
    )
    add_targets_and_outputs_arg(parser)
    return Path.parse_args(parser, args)


def compile_items_to_subvol(
    *,
    exit_stack: ExitStack,
    subvol: Subvol,
    layer_opts: LayerOpts,
    iter_items: Iterator[ImageItem],
    use_threads: bool = True,
) -> None:
    dep_graph = DependencyGraph(
        iter_items=iter_items,
        layer_target=layer_opts.layer_target,
    )
    # Creating all the builders up-front lets phases validate their input
    for builder in [
        builder_maker(items, layer_opts)
        for builder_maker, items in dep_graph.ordered_phases()
    ]:
        builder(subvol)

    # We cannot validate or sort `ImageItem`s until the phases are
    # materialized since the items may depend on the output of the phases.
    for par_items in dep_graph.gen_dependency_order_items(
        PhasesProvideItem(from_target=layer_opts.layer_target, subvol=subvol)
    ):
        if use_threads:
            with concurrent.futures.ThreadPoolExecutor(
                max_workers=len(par_items)
            ) as executor:
                executor.map(
                    lambda item: item.build(subvol, layer_opts), par_items
                )
        else:  # pragma: no cover (only used for profiling)
            for item in par_items:
                # pyre-fixme[16]: `antlir.compiler.items.common.ImageItem` has
                # no attribute `build`.
                item.build(subvol, layer_opts)


def get_parent_layer_flavor_config(parent_layer: Subvol) -> flavor_config_t:
    parent_layer = find_built_subvol(parent_layer)
    flavor = parent_layer.read_path_text(META_FLAVOR_FILE)
    return repo_config().flavor_to_config[flavor]


def invoke_compiler_inside_build_appliance(
    *,
    build_appliance: Subvol,
    argv: List[str],
    snapshot_dir: Path,
    compiler_binary: str,
    subvol_dir: str,
    debug: bool,
):
    opts = new_nspawn_opts(
        cmd=[
            compiler_binary,
            "--is-nested",
            *argv,
        ],
        # Needed to btrfs receive subvol sendstreams
        allow_mknod=True,
        layer=build_appliance,
        user=pwd.getpwnam("root"),
        bind_repo_ro=True,
        bind_artifacts_dir_rw=True,
        hostname=hostname_for_compiler_in_ba(),
    )
    try:
        run_nspawn(
            opts,
            PopenArgs(),
            plugins=rpm_nspawn_plugins(
                opts=opts,
                plugin_args=NspawnPluginArgs(
                    serve_rpm_snapshots=[snapshot_dir],
                    # We'll explicitly call the RPM installer wrapper we need.
                    shadow_proxied_binaries=False,
                ),
            ),
        )
    except CalledProcessError as e:  # pragma: no cover
        # If this failed, it's exceedingly unlikely for this backtrace to
        # actually be useful, and instead it just makes it harder to find the
        # "real" backtrace from the internal compiler. However, in the rare
        # chance that it is useful, ANTLIR_DEBUG voids all warranties for a
        # possibly-actually-readable stderr, and will includ the outer backtrace
        # as well as any inner failures
        if debug:
            raise e
        sys.exit(e.returncode)


def build_image(args: argparse.Namespace, argv: List[str]) -> SubvolumeOnDisk:
    # We want check the umask since it can affect the result of the
    # `os.access` check for `image.install*` items.  That said, having a
    # umask that denies execute permission to "user" is likely to break this
    # code earlier, since new directories wouldn't be traversible.  At least
    # this check gives a nice error message.
    cur_umask = os.umask(0)
    os.umask(cur_umask)
    assert (
        cur_umask & stat.S_IXUSR == 0
    ), f"Refusing to run with pathological umask 0o{cur_umask:o}"

    subvol = Subvol(args.subvolumes_dir / args.subvolume_rel_path)

    flavor_config = args.flavor_config

    if not flavor_config:
        assert (
            args.parent_layer
        ), "Parent layer must be given if no flavor config is given"
        flavor_config = get_parent_layer_flavor_config(args.parent_layer)

    build_appliance = None
    if flavor_config and flavor_config.build_appliance:
        build_appliance_layer_path = args.targets_and_outputs[
            flavor_config.build_appliance
        ]
        build_appliance = find_built_subvol(build_appliance_layer_path)

    # Avoid running the compiler inside of the BA if:
    # 1. The BA isn't set (ie. DO_NOT_USE_BUILD_APPLIANCE). Future: create a
    #    separate lightweight compiler binary for this case.
    # 2. We're already nested inside the BA container.
    # 3. We're compiling a genrule layer. Future: support serving rpm snapshot
    #    in the BA container to remove this restriction.
    if (
        build_appliance
        and not args.is_nested
        and not args.internal_only_is_genrule_layer
    ):
        invoke_compiler_inside_build_appliance(
            build_appliance=build_appliance,
            argv=argv,
            snapshot_dir=not_none(Path(flavor_config.rpm_repo_snapshot)),
            compiler_binary=args.compiler_binary,
            subvol_dir=args.subvolumes_dir,
            debug=args.debug,
        )
    else:
        layer_opts = LayerOpts(
            layer_target=args.child_layer_target,
            build_appliance=build_appliance,
            rpm_installer=YumDnf(flavor_config.rpm_installer),
            rpm_repo_snapshot=Path(flavor_config.rpm_repo_snapshot),
            artifacts_may_require_repo=args.artifacts_may_require_repo,
            target_to_path=args.targets_and_outputs,
            subvolumes_dir=args.subvolumes_dir,
            version_set_override=args.version_set_override,
            debug=args.debug,
            allowed_host_mount_targets=frozenset(
                args.allowed_host_mount_target
            ),
            flavor=flavor_config.name,
            # This value should never be inherited from the parent layer
            # as it is generally used to create a new build appliance flavor
            # by force overriding an existing flavor.
            unsafe_bypass_flavor_check=flavor_config.unsafe_bypass_flavor_check,
        )

        # This stack allows build items to hold temporary state on disk.
        with ExitStack() as exit_stack:
            compile_items_to_subvol(
                exit_stack=exit_stack,
                subvol=subvol,
                layer_opts=layer_opts,
                iter_items=gen_items_for_features(
                    exit_stack=exit_stack,
                    features_or_paths=args.child_feature_json,
                    layer_opts=layer_opts,
                ),
                # use threads to speed up normal builds, but not while profiling
                # because multithreaded profiling is terrible
                use_threads=not args.profile_dir,
            )
            # Build artifacts should never change. Run this BEFORE the
            # exit_stack cleanup to enforce that the cleanup does not
            # touch the image.
            subvol.set_readonly(True)

    try:
        return SubvolumeOnDisk.from_subvolume_path(
            # Converting to a path here does not seem too risky since this
            # class shouldn't have a reason to follow symlinks in the subvol.
            subvol.path(),
            args.subvolumes_dir,
            build_appliance.path() if build_appliance else None,
        )
    # The complexity of covering this is high, but the only thing that can
    # go wrong is a typo in the f-string.
    except Exception as ex:  # pragma: no cover
        raise RuntimeError(f"Serializing subvolume {subvol.path()}") from ex


if __name__ == "__main__":  # pragma: no cover
    from antlir.common import init_logging

    argv = sys.argv[1:]
    args = parse_args(argv)
    init_logging(debug=args.debug)

    with (cProfile.Profile() if args.profile_dir else nullcontext()) as pr:
        try:
            subvol = build_image(args, argv)
            if not args.is_nested:
                subvol.to_json_file(sys.stdout)
        except UserError as e:
            if args.debug:
                raise e
            sys.stderr.write("\n")
            sys.stderr.write(str(e))
            sys.exit(1)
    if args.profile_dir:
        assert pr is not None
        filename = args.child_layer_target.replace("/", "_") + ".pstat"
        os.makedirs(args.profile_dir, exist_ok=True)
        pr.dump_stats(args.profile_dir / filename)
