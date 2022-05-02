/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

use std::path::PathBuf;

use anyhow::{Context, Result};
use metalos_mount::{Mounter, RealMounter};
use structopt::StructOpt;

#[derive(StructOpt)]
pub struct Opts {
    mountpoint: PathBuf,
    #[structopt(short = "c", long = "no-canonicalize")]
    _no_canonicalize: bool,
    #[structopt(short = "f", long = "force")]
    force: bool,
}

pub fn umount(opts: Opts) -> Result<()> {
    RealMounter {}
        .umount(&opts.mountpoint, opts.force)
        .with_context(|| format!("failed to unmount {}", opts.mountpoint.display()))
}
