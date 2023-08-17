#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

set -ex

mkdir -p /foo/bar
echo qux > /foo/bar/baz
rm /empty

empty="$1"
cp "$empty" "/empty-copied-from-location-macro"
