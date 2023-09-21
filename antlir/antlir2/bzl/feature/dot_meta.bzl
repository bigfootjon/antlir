# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

load("//antlir/antlir2/bzl:build_phase.bzl", "BuildPhase")
load("//antlir/antlir2/bzl:macro_dep.bzl", "antlir2_dep")
load(":feature_info.bzl", "FeatureAnalysis", "ParseTimeFeature")

def dot_meta(
        *,
        revision: [str, None] = None,
        package_name: [str, None] = None,
        package_version: [str, None] = None) -> ParseTimeFeature:
    """
    Stamp build info into /.meta in the built layer
    """
    revision = revision or native.read_config("build_info", "revision")
    package_name = package_name or native.read_config("build_info", "package_name")
    package_version = package_version or native.read_config("build_info", "package_version")
    if int(bool(package_name)) ^ int(bool(package_version)):
        warning("Only one of {package_name, package_version} was set; package info will not be materialized into .meta")

    package = None
    if package_name and package_version:
        package = package_name + ":" + package_version

    build_info = {
        "package": package,
        "revision": revision,
    }
    return ParseTimeFeature(
        feature_type = "dot_meta",
        impl = antlir2_dep("features:dot_meta"),
        kwargs = {
            "build_info": build_info,
        },
    )

build_info_record = record(
    revision = [str, None],
    package = [str, None],
)

dot_meta_record = record(
    build_info = [build_info_record, None],
)

def dot_meta_analyze(
        build_info: [dict[str, typing.Any], None],
        impl: RunInfo) -> FeatureAnalysis:
    return FeatureAnalysis(
        feature_type = "dot_meta",
        data = dot_meta_record(
            build_info = build_info_record(**build_info) if build_info else None,
        ),
        build_phase = BuildPhase("buildinfo_stamp"),
        impl_run_info = impl,
    )
