import std/unittest
import std/sugar
import std/strutils

import reactiveCrown/core
import reactiveCrown/subjects

import reactiveCrown/operators/operator_concept {.all.}
import reactiveCrown/operators/operator_map {.all.}
import reactiveCrown/operators/operator_filter {.all.}


operator_map.test
operator_filter.test