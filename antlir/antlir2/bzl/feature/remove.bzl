# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

load("//antlir/antlir2/bzl:build_phase.bzl", "BuildPhase")
load(":feature_info.bzl", "ParseTimeFeature", "data_only_feature_analysis_fn")

def remove(
        *,
        path: str,
        must_exist: bool = True) -> ParseTimeFeature.type:
    """
    Recursivel remove a file or directory

    These are allowed to remove paths inherited from the parent layer, or those
    installed in this layer.

    By default, it is an error if the specified path is missing from the image,
    though this can be avoided by setting `must_exist=False`.
    """
    return ParseTimeFeature(
        feature_type = "remove",
        impl = "//antlir/antlir2/features:remove",
        kwargs = {
            "must_exist": must_exist,
            "path": path,
        },
    )

remove_record = record(
    path = str.type,
    must_exist = bool.type,
)

remove_analyze = data_only_feature_analysis_fn(
    remove_record,
    feature_type = "remove",
    build_phase = BuildPhase("remove"),
)
