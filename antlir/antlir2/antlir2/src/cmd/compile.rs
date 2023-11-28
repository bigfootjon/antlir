/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

use antlir2_compile::plan::Plan;
use antlir2_compile::CompileFeature;
use clap::Parser;
use json_arg::JsonFile;

use super::Compileish;
use crate::Result;

#[derive(Parser, Debug)]
/// Compile image features into a directory
pub(crate) struct Compile {
    #[clap(flatten)]
    pub(super) compileish: Compileish,
    #[clap(flatten)]
    /// Pre-computed plan for this compilation phase
    pub(super) external: CompileExternal,
}

#[derive(Parser, Debug)]
/// Compile arguments that are _always_ passed from external sources (in other
/// words, by buck2 actions) and are never generated by internal code in the
/// 'isolate' subcommand.
pub(super) struct CompileExternal {
    #[clap(long)]
    /// Pre-computed plan for this compilation phase
    plan: Option<JsonFile<Plan>>,
}

impl Compile {
    #[tracing::instrument(name = "compile", skip(self), ret, err)]
    pub(crate) fn run(self) -> Result<()> {
        let ctx = self
            .compileish
            .compiler_context(self.external.plan.map(JsonFile::into_inner))?;
        for feature in self.compileish.external.depgraph.pending_features() {
            feature.compile(&ctx)?;
        }
        Ok(())
    }
}
