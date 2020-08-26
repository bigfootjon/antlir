#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import importlib.resources
import os
import subprocess
import tempfile
import unittest

from fs_image.vm.share import Share


TEST_SHARES = [
    Share(path="/tmp/hello"),
    Share(path="/usr/tag", mount_tag="explicit_tag"),
    Share(path="/tmp/not-included", generator=False),
]

UNITS = {"tmp-hello.mount", "usr-tag.mount"}


class TestShareGenerator(unittest.TestCase):
    def test_export_spec(self):
        with Share.export_spec(TEST_SHARES) as share:
            with open(os.path.join(share.path, "exports")) as f:
                self.assertEqual(
                    f.read(), "fs0 /tmp/hello\nexplicit_tag /usr/tag\n"
                )

    def test_units(self):
        with importlib.resources.path(
            __package__, "9p-mount-generator"
        ) as generator, Share.export_spec(
            TEST_SHARES
        ) as share, tempfile.TemporaryDirectory() as outdir:
            subprocess.run(
                [generator, outdir], env={"EXPORTS_DIR": share.path}, check=True
            )

            self.assertEqual(
                set(os.listdir(outdir)),
                UNITS.union({"local-fs.target.requires"}),
            )
            # check that the mount units have the expected content
            with open(os.path.join(outdir, "usr-tag.mount")) as f:
                self.assertEqual(
                    f.read(),
                    """[Unit]
Requires=systemd-modules-load.service
After=systemd-modules-load.service
Before=local-fs.target
RequiredBy=local-fs.target

[Mount]
What=explicit_tag
Where=/usr/tag
Type=9p
Options=version=9p2000.L,posixacl,cache=loose,ro
""",
                )

            # check that depencies are setup correclty
            self.assertEqual(
                set(
                    os.listdir(os.path.join(outdir, "local-fs.target.requires"))
                ),
                UNITS,
            )
            for unit in UNITS:
                self.assertEqual(
                    os.readlink(
                        os.path.join(outdir, "local-fs.target.requires", unit)
                    ),
                    os.path.join(outdir, unit),
                )
