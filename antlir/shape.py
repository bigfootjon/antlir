#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# Python runtime component of shape.bzl. This file is not meant to be used
# directly, instead it contains supporting implementations for bzl/shape.bzl.
# See that file for motivations and usage documentation.

import enum
import importlib.resources
import os
from typing import Type, TypeVar, Union

import pydantic
from antlir.freeze import DoNotFreeze, freeze
from antlir.fs_utils import Path


S = TypeVar("S")


class ShapeMeta(pydantic.main.ModelMetaclass):
    def __new__(metacls, name, bases, dct):  # noqa: B902
        cls = super().__new__(metacls, name, bases, dct)
        # Only apply shape meta hacks to generated classes, not user-written
        # subclasses
        cls.__GENERATED_SHAPE__ = dct.get("__GENERATED_SHAPE__", False)
        if cls.__GENERATED_SHAPE__:
            cls.__name__ = repr(cls)
            cls.__qualname__ = repr(cls)

            # create an inner class `types` to make all the fields types usable
            # from a user of shape without having to know the cryptic generated
            # class names
            if "types" in dct or "types" in dct.get("__annotations__", {}):
                raise KeyError("'types' cannot be used as a shape field name")
            types_cls = {}
            for key, f in cls.__fields__.items():
                types_cls[key] = f.type_
            cls.types = type("types", (object,), types_cls)

        return cls

    # pyre-fixme[14]: `__repr__` overrides method defined in `object` inconsistently.
    def __repr__(cls) -> str:  # noqa: B902
        """
        Human-readable class __repr__, that hides the ugly autogenerated
        shape class names.
        """
        fields = ", ".join(
            f"{key}={f._type_display()}"
            # pyre-fixme[16]: `ShapeMeta` has no attribute `__fields__`.
            for key, f in cls.__fields__.items()
        )
        clsname = "shape"
        # pyre-fixme[16]: `ShapeMeta` has no attribute `__GENERATED_SHAPE__`.
        if not cls.__GENERATED_SHAPE__:
            clsname = cls.__name__
        return f"{clsname}({fields})"


class Shape(pydantic.BaseModel, DoNotFreeze, metaclass=ShapeMeta):
    class Config:
        allow_mutation = False

    def __init__(self, *args, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        for k, v in self.__dict__.items():
            self.__dict__[k] = freeze(v)

    @classmethod
    def read_resource(cls: Type[S], package: str, name: str) -> S:
        with importlib.resources.open_text(package, name) as r:
            # pyre-fixme[16]: `S` has no attribute `parse_raw`.
            return cls.parse_raw(r.read())

    @classmethod
    def load(cls: Type[S], path: Union[Path, str]) -> S:
        with open(path, "r") as r:
            # pyre-fixme[16]: `S` has no attribute `parse_raw`.
            return cls.parse_raw(r.read())

    @classmethod
    def from_env(cls: Type[S], envvar: str) -> S:
        # pyre-fixme[16]: `S` has no attribute `parse_raw`.
        return cls.parse_raw(os.environ[envvar])

    def __hash__(self) -> int:
        return hash((type(self), *self.__dict__.values()))

    def __repr__(self) -> str:
        """
        Human-readable instance __repr__, that hides the ugly autogenerated
        shape class names.
        """
        # pyre-fixme[16]: `Shape` has no attribute `__GENERATED_SHAPE__`.
        if not type(self).__GENERATED_SHAPE__:
            return super().__repr__()
        # print only the set fields in the defined order
        fields = ", ".join(
            f"{key}={repr(getattr(self, key))}" for key in self.__fields__
        )
        return f"shape({fields})"


class Enum(enum.Enum):
    def __repr__(self) -> str:
        return self.name

    def __eq__(self, o: object):  # pragma: no cover
        # it can sometimes be hard to get the exact same instance of this enum
        # class due to the way the codegen works, so allow comparisons by value
        # as well as the normal identity-based comparison
        if hasattr(o, "value"):
            # pyre-fixme[16]: `object` has no attribute `value`.
            return self.value == o.value
        return super().__eq__(o)
