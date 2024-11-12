/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

use anyhow::Result;
use clap::Parser;

mod runtime;
mod spawn;

pub(crate) use runtime::RuntimeSpec;

#[derive(Parser, Debug)]
enum Args {
    /// Spawn a container to run the test
    Spawn(spawn::Args),
}

fn main() -> Result<()> {
    tracing_subscriber::fmt::init();

    let args = Args::parse();

    match args {
        Args::Spawn(a) => a.run(),
    }
}
