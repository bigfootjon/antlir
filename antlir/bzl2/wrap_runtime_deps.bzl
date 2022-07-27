# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# @lint-ignore-every BUCKLINT

load("//antlir/bzl:oss_shim.bzl", "is_buck2")
load("//antlir/bzl:target_helpers.bzl", "antlir_dep")
load(
    "//antlir/bzl:wrap_runtime_deps.bzl",
    helper = "maybe_wrap_executable_target",
)

def _wrap_executable_target_rule_impl(ctx):
    if not ctx.attrs.target[native.RunInfo]:
        return [native.DefaultInfo()]

    path_in_output = \
        "/" + ctx.attrs.path_in_output if ctx.attrs.path_in_output else ""

    create_wrapper_script = ctx.actions.declare_output("create_wrapper.sh")
    output = ctx.actions.declare_output("out")

    script = """
set -exo pipefail
echo "#!/bin/bash
REPO_ROOT=`$repo_root`
{unquoted_heredoc_preamble}
$literal_preamble
exec \\$REPO_ROOT/$runnable$path_in_output {args}" > $OUT
chmod +x $OUT
    """.format(
        # Necessary because script generated here differs from that generated in
        # `exec_wrapper.bzl`, which uses the same thing
        unquoted_heredoc_preamble = ctx.attrs.unquoted_heredoc_preamble.replace(
            "\\$(date)",
            "$(date)",
        ),
        args = '"\\$@"',
    )
    ctx.actions.write(
        create_wrapper_script,
        script,
    )

    ctx.actions.run(
        native.cmd_args(["/bin/bash", create_wrapper_script]),
        env = {
            "OUT": output.as_output(),
            "literal_preamble": ctx.attrs.literal_preamble,
            "path_in_output": path_in_output,
            "repo_root": ctx.attrs.repo_root[native.RunInfo],
            "runnable": ctx.attrs.target[native.RunInfo],
        },
        # See comment at https://fburl.com/code/3pj7exvp
        local_only = True,
        category = "wrap_executable_target",
        identifier = "create_wrapper",
    )

    return [native.DefaultInfo(default_outputs = [output])]

_wrap_executable_target_rule = native.rule(
    impl = _wrap_executable_target_rule_impl,
    attrs = {
        "literal_preamble": native.attrs.arg(),
        "path_in_output": native.attrs.string(default = ""),
        "repo_root": native.attrs.dep(),
        "target": native.attrs.dep(),
        "unquoted_heredoc_preamble": native.attrs.string(),
    },
) if is_buck2() else None

def maybe_wrap_executable_target_rule(**kwargs):
    if not native.rule_exists(kwargs.get("name")):
        _wrap_executable_target_rule(
            repo_root = antlir_dep(":repo-root"),
            **kwargs
        )

    return ":" + kwargs.get("name")

def maybe_wrap_executable_target(target, wrap_suffix, **kwargs):
    kwargs.update({"wrap_rule_fn": maybe_wrap_executable_target_rule})
    return helper(target, wrap_suffix, **kwargs)
