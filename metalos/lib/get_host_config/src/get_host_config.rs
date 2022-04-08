/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

use anyhow::{anyhow, Context, Result};
use fbthrift::simplejson_protocol::deserialize;
use metalos_host_configs::host::HostConfig;
use reqwest::Client;
use std::path::Path;
use url::Url;

pub fn client() -> Result<Client> {
    Client::builder()
        .trust_dns(true)
        .use_rustls_tls()
        .build()
        .context("building client")
}

pub fn get_host_config_from_file(path: &Path) -> Result<HostConfig> {
    let blob =
        std::fs::read(path).with_context(|| format!("while opening file {}", path.display()))?;
    deserialize(blob).context("while deserializing from json")
}

pub async fn get_host_config(uri: &Url) -> Result<HostConfig> {
    match uri.scheme() {
        "http" | "https" => {
            let client = client()?;
            let bytes = client
                .get(uri.clone())
                .send()
                .await
                .with_context(|| format!("while GETting {}", uri))?
                .bytes()
                .await
                .context("while downloading host json")?;
            deserialize(bytes).context("while deserializing from json")
        }
        "file" => get_host_config_from_file(Path::new(uri.path())),
        scheme => Err(anyhow!("Unsupported scheme {} in {:?}", scheme, uri)),
    }
}
