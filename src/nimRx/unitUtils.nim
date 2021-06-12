## | When using this module, please import it explicitly.
## | This module is based on the Unit type found in UniRx, ReactiveX for Unity.
## 
## Usage with using unitUtils
## --------------------------
runnableExamples:
  import nimRx
  import nimRx/unitUtils

  var isOnNextThrown: array[2, bool]
  let
    sbj = newSubject[Unit]()
    obs = sbj.asObservable
      .buffer(2, 1)

  discard obs
    .unitfy()
    .subscribeBlock:
      isOnNextThrown[0] = true

  discard obs
    .subscribeBlock:
      isOnNextThrown[1] = true

  sbj.onNext()
  sbj.onNext()
  doAssert isOnNextThrown[0]
  doAssert isOnNextThrown[1]


import sugar

import core
import subjects
import operators

type Unit* = ref object

proc unitDefault*(): Unit = new Unit

proc unitfy*[T](upstream: IObservable[T]): IObservable[Unit] =
  blueprint[Unit]:
    newIObservable[Unit] proc(observer: Observer[Unit]): IDisposable =
      upstream.subscribe(
        (v: T) => observer.onNext unitDefault(),
        (e: Error) => observer.onError e,
        () => observer.onCompleted(),
      )

template subscribeBlock*(upstream: IObservable[Unit];
    body: untyped): IDisposable =
  upstream.subscribe((_: Unit) => body)

template subscribeBlock*[T](upstream: IObservable[T];
    body: untyped): IDisposable =
  upstream.unitfy().subscribe((_: Unit) => body)

template onNext*(subject: Subject[Unit]): void =
  subject.onNext(unitDefault())
