/*
 * Copyright (c) Meta Platforms, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

namespace cpp2 metalos.host_configs
namespace py3 metalos.host_configs

include "metalos/host_configs/packages.thrift"
// @oss-disable: include "metalos/host_configs/facebook/proxy/if/deployment_specific.thrift"

// Complete boot-time config for a MetalOS host. Requires a reboot to update.
struct BootConfig {
  // @oss-disable: 1: deployment_specific.DeploymentBootConfig deployment_specific;
  2: packages.Rootfs rootfs;
  3: packages.Kernel kernel;
} (rust.exhaustive)
