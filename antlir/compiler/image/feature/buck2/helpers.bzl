# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# @lint-ignore-every BUCKRESTRICTEDSYNTAX

load("@bazel_skylib//lib:new_sets.bzl", "sets")
load("@bazel_skylib//lib:types.bzl", "types")
load("//antlir/bzl:constants.bzl", "REPO_CFG")
load("//antlir/bzl:sha256.bzl", "sha256_b64")
load("//antlir/bzl:shape.bzl", "shape")
load("//antlir/bzl:target_helpers.bzl", "normalize_target")
load("//antlir/bzl:wrap_runtime_deps.bzl", "maybe_wrap_executable_target")
load(
    "//antlir/bzl/image/feature:new.bzl",
    "PRIVATE_DO_NOT_USE_feature_target_name",
)

def _clean_arg_to_str(arg):
    # chars that can be included in target name.
    valid_target_chars = sets.make(
        (
            "ABCDEFGHIJKLMNOPQRSTUVWXYZ" +
            "abcdefghijklmnopqrstuvwxyz" +
            "0123456789" +
            "_,.=-\\~@!+$"
        ).split(""),
    )

    # chars that can't be included in target name and should also be entirely
    # removed from `str(arg)` (replaced with ""). All characters not in
    # `remove_chars` and not in `valid_target_chars` are replaced with
    # underscores to improve readability.
    remove_chars = sets.make("][}{)(\"' ".split(""))

    return "".join(
        [
            char if sets.contains(valid_target_chars, char) else "_"
            for char in str(arg).split("")
            if not sets.contains(remove_chars, char)
        ],
    )

def generate_feature_target_name(
        name,
        key,
        feature_shape,
        include_in_name = None):
    """
    Generate a memoization-safe target name for features.

    - `name`: type of feature
    - `feature_shape`: feature shape generated in `feature_{name}`
    - `include_in_name`: feature arguments that are wanted in their original
        form (perhaps for debugging purposes).
    """

    if include_in_name:
        # only include collections if they are not empty in name
        include_in_name = sorted(
            filter(
                lambda x: x[1] or x[1] == 0,
                include_in_name.items(),
            ),
        )

    include_in_name_str = (
        "".join(
            [
                "{arg_name}_{arg}_".format(
                    arg_name = arg_name.upper(),
                    arg = _clean_arg_to_str(arg),
                )
                for arg_name, arg in include_in_name
            ],
        )[:-1] if include_in_name else ""
    )

    # if list of feature shapes is provided, hash all shapes, join their hashes
    # and then hash that final string to obtain `shape_hash`.
    if types.is_list(feature_shape):
        shape_hash = sha256_b64("_".join(sorted([
            sha256_b64(shape.do_not_cache_me_json(s))
            for s in feature_shape
        ])))
    else:
        shape_hash = sha256_b64(shape.do_not_cache_me_json(feature_shape))

    return PRIVATE_DO_NOT_USE_feature_target_name(
        "antlir_feature__{name}__KEY_{key}__{include_in_name}__{shape_hash}".format(
            name = name,
            key = key,
            include_in_name = include_in_name_str,
            shape_hash = shape_hash,
        ),
    )

def mark_path(target, is_layer = False):
    return {("__BUCK_LAYER_TARGET" if is_layer else "__BUCK_TARGET"): normalize_target(target)}

def unwrap_path(path_dict, is_layer = False):
    return path_dict["__BUCK_LAYER_TARGET" if is_layer else "__BUCK_TARGET"]

def _mark_path_and_get_target(source_dict, key, is_layer = False):
    if type(source_dict[key]) == dict:
        fail("Path already marked for `{key}` in `{source_dict}`".format(
            key = key,
            source_dict = source_dict,
        ))
    source_dict[key] = mark_path(source_dict[key], is_layer)
    normalized_target = unwrap_path(source_dict[key], is_layer)
    return normalized_target

def normalize_target_and_mark_path_in_source_dict(source_dict, **kwargs):
    """
    Adds tag to target at `source_dict[{source,layer,generator}}]` and
    normalizes target so target can be converted to path in
    items_for_features.py.
    """
    if not (source_dict.get("source") or
            source_dict.get("generator") or
            source_dict.get("layer")):
        fail("One of source, generator, layer must contain a target")

    if source_dict.get("source"):
        normalized_target = _mark_path_and_get_target(source_dict, "source")

        if kwargs.get("is_buck_runnable"):
            was_wrapped, source_dict["source"] = maybe_wrap_executable_target(
                target = unwrap_path(source_dict["source"]),
                wrap_suffix = "install_buck_runnable_wrap_source",
                visibility = None,
                # NB: Buck makes it hard to execute something out of an
                # output that is a directory, but it is possible so long as
                # the rule outputting the directory is marked executable
                # (see e.g. `print-ok-too` in `feature_install_files`).
                path_in_output = source_dict.get("path", None),
                runs_in_build_steps_causes_slow_rebuilds =
                    kwargs.get("runs_in_build_steps_causes_slow_rebuilds"),
            )
            if was_wrapped:
                # The wrapper above has resolved `source_dict["path"]`, so the
                # compiler does not have to.
                source_dict["path"] = None
            normalized_target = _mark_path_and_get_target(source_dict, "source")

    elif source_dict.get("generator"):
        _was_wrapped, source_dict["generator"] = maybe_wrap_executable_target(
            target = source_dict["generator"],
            wrap_suffix = "image_source_wrap_generator",
            visibility = [],  # Not visible outside of project
            # Generators run at build-time, that's the whole point.
            runs_in_build_steps_causes_slow_rebuilds = True,
        )
        normalized_target = _mark_path_and_get_target(source_dict, "generator")

    else:
        normalized_target = _mark_path_and_get_target(
            source_dict,
            "layer",
            is_layer = True,
        )

    return source_dict, normalized_target

def is_build_appliance(target):
    return target in {
        config.build_appliance: 1
        for _, config in REPO_CFG.flavor_to_config.items()
    }

def _self_test_generate_feature_target_name():
    test_shape = shape.shape(
        str_f = shape.field(str, optional = True),
        int_f = shape.field(int, optional = True),
        dict_f = shape.field(shape.dict(str, str), optional = True),
    )

    test_shape_1 = test_shape(
        str_f = "foo",
        int_f = 12345,
    )
    test_shape_2 = test_shape(
        str_f = "bar",
        dict_f = {
            "bar": "baz",
            "foo": "bar",
        },
    )

    test_1 = generate_feature_target_name(
        name = "foo",
        key = "key1",
        feature_shape = test_shape_1,
        include_in_name = {
            "bar": ["baz"],
        },
    )
    test_2 = generate_feature_target_name(
        name = "bar",
        key = "key2",
        feature_shape = [test_shape_1, test_shape_2],
        include_in_name = {
            "bar": [],
        },
    )

    test_1_answer = (
        "antlir_feature__foo__KEY_key1__BAR_baz__" +
        "bINw2KkLqCDPdHGk1Zq3xcFnfHpglxM_H4v2UxBoj80" +
        "_IF_YOU_REFER_TO_THIS_RULE_YOUR_DEPENDENCIES_WILL_BE_BROKEN"
    )
    test_2_answer = (
        "antlir_feature__bar__KEY_key2____" +
        "Msq-FeroZIXLzlGnQB3B16882r8szecaypH7YMcB9Q0" +
        "_IF_YOU_REFER_TO_THIS_RULE_YOUR_DEPENDENCIES_WILL_BE_BROKEN"
    )

    if test_1 != test_1_answer or test_2 != test_2_answer:
        fail(
            "{function} failed test".format(
                function = "generate_feature_target_name",
            ),
        )

_self_test_generate_feature_target_name()
