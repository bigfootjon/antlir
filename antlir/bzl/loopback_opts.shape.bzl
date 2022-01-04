# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

load(":shape.bzl", "shape")

loopback_opts_t = shape.shape(
    # Size of the target image in MiB
    size_mb = shape.field(int, optional = True),
    label = shape.field(str, optional = True),
    # Note: These options are for btrfs loopbacks only. Ideally they would
    # be defined in their own shape type, but nested shape types
    # are hard to use from python because the type name is not
    # known.  Until that issue is fixed, we will just embed these
    # here.
    #
    # Optionally force enable/disable the minimization of a btrfs
    # loopback.  By default, if the the package is built when
    # REPO_CFG.artifacts_require_repo == False it will be minimized.
    # In some situations, it is desireable to control this behavior
    # explicitly.
    minimize_size = shape.field(bool, default = False),
    writable_subvolume = shape.field(bool, default = False),
    seed_device = shape.field(bool, default = False),
    default_subvolume = shape.field(bool, default = False),
    subvol_name = shape.field(str, optional = True),
    # vfat-only options
    fat_size = shape.field(int, optional = True),
)
