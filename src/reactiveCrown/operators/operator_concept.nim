{.deadCodeElim.}
import std/sugar
import ../core

type
  OperatorObservable*[T] = object
    OnSubscribe: (ptr OperatorObservable[T], Observer[T]) -> Disposable
    disposable :Disposable

proc onSubscribe*[T](observable: var OperatorObservable[T]; observer: Observer[T]): Disposable =
  observable.OnSubscribe(observable.addr, observer)

func `^++`(x: var int): int {.inline, used.} = result = x; inc x