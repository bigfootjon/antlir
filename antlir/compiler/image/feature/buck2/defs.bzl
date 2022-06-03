# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

load("//antlir/compiler/image/feature/buck2:new.bzl", "feature_new")
load("//antlir/compiler/image/feature/buck2:remove.bzl", "feature_remove")

feature = struct(
    new = feature_new,
    remove = feature_remove,
)
