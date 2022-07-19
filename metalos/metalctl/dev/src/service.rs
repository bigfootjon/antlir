/*
 * Copyright (c) Meta Platforms, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

use std::ffi::OsString;
use std::os::unix::process::CommandExt;

use anyhow::Context;
use anyhow::Result;
use clap::Parser;
use slog::debug;
use slog::Logger;

use metalos_host_configs::packages::Format;
use metalos_host_configs::packages::Service as ServicePackage;
use metalos_host_configs::runtime_config::Service;
use package_download::ensure_package_on_disk;
use package_download::HttpsDownloader;
use service::ServiceSet;
use service::Transaction;
use systemd::Systemd;

use crate::PackageArg;
use crate::SendstreamPackage;

#[derive(Parser)]
pub(crate) enum Opts {
    /// Start specific versions of a set of native services, replacing the
    /// running version if necessary.
    Start(Start),
    /// Stop a set of native services
    Stop(Stop),
    /// Enter a native service's namespaces
    Enter(Enter),
}

impl<F: crate::FormatArg> From<&PackageArg<F>> for Service {
    fn from(sid: &PackageArg<F>) -> Service {
        Service {
            svc: ServicePackage::new(sid.name.clone(), sid.uuid, None, Format::Sendstream),
            config_generator: None,
        }
    }
}

#[derive(Parser)]
pub(crate) struct Start {
    services: Vec<PackageArg<SendstreamPackage>>,
}

#[derive(Parser)]
pub(crate) struct Stop {
    services: Vec<String>,
}

#[derive(Parser)]
pub(crate) struct Enter {
    service: String,
    #[clap(help = "program to exec inside nsenter")]
    prog: Vec<OsString>,
}

pub(crate) async fn service(log: Logger, opts: Opts) -> Result<()> {
    let sd = Systemd::connect(log.clone()).await?;
    match opts {
        Opts::Start(start) => {
            let dl = HttpsDownloader::new().context("while creating downloader")?;
            for svc in &start.services {
                let svc: Service = svc.into();
                ensure_package_on_disk(log.clone(), &dl, svc.svc).await?;
            }

            let mut set = ServiceSet::current(&sd).await?;
            for svc in start.services {
                set.insert(svc.name, svc.uuid);
            }
            let tx = Transaction::with_next(&sd, set).await?;
            tx.commit(log, &sd).await?;
        }
        Opts::Stop(stop) => {
            let mut set = ServiceSet::current(&sd).await?;
            for name in stop.services {
                set.remove(&name);
            }
            let tx = Transaction::with_next(&sd, set).await?;
            tx.commit(log, &sd).await?;
        }
        Opts::Enter(enter) => {
            let service = match enter.service.ends_with(".service") {
                true => enter.service,
                false => format!("{}.service", enter.service),
            };
            let unit = sd
                .get_service_unit(&service.clone().into())
                .await
                .with_context(|| format!("could not get service {}", service))?;

            let pid = unit
                .main_pid()
                .await
                .with_context(|| format!("could not get MainPID of {}", service))?;

            debug!(log, "{} MainPID={}", service, pid);

            Err(std::process::Command::new("nsenter")
                .arg("--all")
                .arg("--target")
                .arg(pid.to_string())
                .arg("--")
                .args(enter.prog)
                .exec())
            .with_context(|| format!("while execing 'nsenter --all target {}'", pid))?;
        }
    }
    Ok(())
}
