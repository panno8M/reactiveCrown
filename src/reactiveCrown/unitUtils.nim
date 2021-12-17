## | When using this module, please import it explicitly.
## | This module is based on the Unit type found in UniRx, ReactiveX for Unity.
## 
## Usage with using unitUtils
## --------------------------
runnableExamples:
  import reactiveCrown
  import reactiveCrown/unitUtils

  var isOnNextThrown: array[2, bool]
  let
    sbj = newPublishSubject[Unit]()
    obs = sbj.toObservable
      .buffer(2, 1)

  obs
    .unitfy()
    .subscribeBlock:
      isOnNextThrown[0] = true

  obs
    .subscribeBlock:
      isOnNextThrown[1] = true

  sbj.next
  sbj.next
  doAssert isOnNextThrown[0]
  doAssert isOnNextThrown[1]


import sugar

import core
import subjects
import operators

type Unit* = ref object

proc unitDefault*(): Unit = new Unit

proc unitfy*[T](upstream: Observable[T]): Observable[Unit] =
  construct_whenSubscribed[Unit]():
    newObservable[Unit] proc(observer: Observer[Unit]): Disposable =
      upstream.subscribe(
        (v: T) => observer.next unitDefault(),
        (e: ref Exception) => observer.error e,
        () => observer.complete,
      )

template subscribeBlock*(upstream: Observable[Unit];
    body: untyped): Disposable =
  upstream.subscribe((_: Unit) => body)

template subscribeBlock*[T](upstream: Observable[T];
    body: untyped): Disposable =
  upstream.unitfy().subscribe((_: Unit) => body)

proc next*(subject: ConceptSubject[Unit]) {.inline.} =
  subject.next(unitDefault())
