# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from typing import Optional

class Label:
    def __init__(s: str) -> None: ...
    def __str__(self) -> str: ...
    @property
    def cell(self) -> str: ...
    @property
    def package(self) -> str: ...
    @property
    def name(self) -> str: ...
    @property
    def config(self) -> Optional[Label]: ...
    @property
    def unconfigured(self) -> Label: ...
