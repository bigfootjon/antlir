# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

load("//antlir/antlir2/bzl:compat.bzl?v2_only", antlir2_compat = "compat")
load("//antlir/antlir2/bzl/feature:antlir1_no_equivalent.bzl?v2_only", "antlir1_no_equivalent")
load("//antlir/antlir2/bzl/image:defs.bzl?v2_only", antlir2_image = "image")
load("//antlir/bzl:build_defs.bzl", "alias", "get_visibility", "is_buck2")
load("//antlir/bzl:from_package.shape.bzl", "layer_from_package_t")
load("//antlir/bzl:image_source.bzl", "image_source_to_buck2_src")
load("//antlir/bzl/image/feature:new.bzl", "PRIVATE_DO_NOT_USE_feature_target_name")
load(":antlir2_shim.bzl", "antlir2_shim")
load(":compile_image_features.bzl", "compile_image_features")
load(":constants.bzl", "use_rc_target")
load(":flavor_impl.bzl", "flavor_to_struct")
load(":image_layer_alias.bzl", "image_layer_alias")
load(":image_layer_utils.bzl", "image_layer_utils")
load(":target_helpers.bzl", "normalize_target")
load(":target_tagger.bzl", "extract_tagged_target", "image_source_as_target_tagged_dict", "new_target_tagger", "target_tagger_to_feature")
load(":target_tagger.shape.bzl", "target_tagged_image_source_t")

def image_layer_from_package_helper(
        name,
        format,
        flavor,
        flavor_config_override,
        antlir_rule,
        rc_layer,
        features,
        compile_image_features_fn,
        image_layer_kwargs,
        antlir2_src):
    flavor = flavor_to_struct(flavor)
    target = normalize_target(":" + name)
    antlir2 = antlir2_shim.should_make_parallel_layer(image_layer_kwargs.pop("antlir2", None), flavor = flavor)

    # Do argument validation
    for bad_kwarg in ["parent_layer", "features"]:
        if bad_kwarg in image_layer_kwargs:
            fail("Unsupported with layer_from_package", bad_kwarg)
    if format not in ["sendstream", "sendstream.v2"]:
        fail("Unsupported format for layer_from_package", format)
    if rc_layer != None:
        # If rc_layer was specified, create an unused layer alias that depends
        # on it to ensure the target exists and is visible. This ensures that
        # building with "-c antlir.rc_targets=XXX" won't fail.
        image_layer_alias(
            name = PRIVATE_DO_NOT_USE_feature_target_name(name),
            antlir2 = False,
            layer = rc_layer,
        )
    if use_rc_target(exact_match = True, target = target) and rc_layer == None:
        fail("{}'s rc build was requested but `rc_layer` is unset!".format(target))

    if use_rc_target(target = target) and rc_layer != None:
        image_layer_alias(
            name = name,
            layer = rc_layer,
            antlir2 = antlir2,
        )
        if antlir2:
            alias(
                name = name + ".antlir2",
                antlir_rule = "user-internal",
                layer = rc_layer + ".antlir2",
                visibility = get_visibility(image_layer_kwargs.get("visibility")),
            )
    else:
        _make_subvol_cmd, _deps_query = compile_image_features_fn(
            name = name,
            current_target = normalize_target(":" + name),
            features = features,
            flavor = flavor,
            flavor_config_override = flavor_config_override,
            parent_layer = None,
        )

        if antlir2:
            if is_buck2():
                antlir2_image.prebuilt(
                    name = name + ".antlir2",
                    src = antlir2_src,
                    flavor = antlir2_compat.from_antlir1_flavor(flavor),
                    format = format,
                    visibility = get_visibility(image_layer_kwargs.get("visibility")),
                )
            else:
                antlir2_shim.fake_buck1_target(name + ".antlir2")
        image_layer_utils.image_layer_impl(
            _rule_type = "image_layer_from_package",
            _layer_name = name,
            _make_subvol_cmd = _make_subvol_cmd,
            _deps_query = _deps_query,
            antlir_rule = antlir_rule,
            **image_layer_kwargs
        )

# See the `_image_layer_impl` signature (in `image_layer_utils.bzl`) for all
# other supported kwargs.
def image_layer_from_package(
        name,
        format,
        source = None,
        flavor = None,
        flavor_config_override = None,
        # A sendstream layer does not add any build logic on top of the
        # input, so we treat it as internal to improve CI coverage.
        antlir_rule = "user-internal",
        # The target path of the rc-layer implementation that built this
        # packaged layer.  Used in conjunction with the `-c antlir.rc.layers`
        # config to test changes to packaged layers.
        rc_layer = "__unset__",
        # Mechanistically, applying a send-stream on top of an existing layer
        # is just a regular `btrfs receive`.  However, the rules in the
        # current `receive` implementation for matching the parent to the
        # stream are kind of awkward, and it's not clear whether they are
        # right for us in Buck.
        **image_layer_kwargs):
    """
    Arguments
    - `format`: The format of the package the layer is created from. Supported
    formats include `sendstream` and `tar`.
    - `name`, `source`, etc: same as on `image_layer.bzl`.
    The only unsupported kwargs are `parent_layer`
    (we'll support incremental sendstreams eventually) and
    `features` (make your changes in a child layer).
    """
    if rc_layer == "__unset__":
        fail("rc_layer must be specified or explicitly set to None")
    flavor = flavor_to_struct(flavor)
    target_tagger = new_target_tagger()
    source_dict = image_source_as_target_tagged_dict(
        target_tagger,
        source,
    )

    feature_shape = layer_from_package_t(
        format = format,
        source = target_tagged_image_source_t(**source_dict),
    )
    source_target = extract_tagged_target(
        source_dict["source" if source_dict["source"] else "layer"],
    )

    features = [target_tagger_to_feature(
        target_tagger,
        struct(
            layer_from_package = [feature_shape],
        ),
        antlir2_feature = antlir1_no_equivalent(description = "image_layer_from_package", label = normalize_target(":" + name)) if is_buck2() else None,
    )]

    buck2_src = image_source_to_buck2_src(source)

    image_layer_from_package_helper(
        name,
        format,
        flavor,
        flavor_config_override,
        antlir_rule,
        rc_layer,
        features,
        compile_image_features,
        image_layer_kwargs,
        antlir2_src = buck2_src,
    )
