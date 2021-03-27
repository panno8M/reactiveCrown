# import sugar, sequtils, strformat, strutils

type
  Unit* = ref object
  # TODO: define error type
  Error* = ref object
    msg: string

  fn[T] = proc(v: T): void
  fe = proc(e: Error): void
  fc = proc(): void

  Observer*[T] = ref object of RootObj
    onNext*: fn[T]
    onError*: fe
    onCompleted*: fc
  Observable*[T] = ref object of RootObj
    observers*: seq[Observer[T]]
    onSubscribe*: fn[Observer[T]]
    completed*: bool
  Disposable*[T] = ref object of RootObj
    observable: Observable[T]
    observer: Observer[T]
    disposed: bool

proc doNothing[T](v: T): void = discard
proc doNothing(): void = discard

proc unitDefault*(): Unit = new Unit

proc newError*(msg: string): Error =
  Error(msg: msg)
proc `$`*(e: Error): string = e.msg

## *Disposable ==========================================================================
proc newDisposable*[T](observable: Observable[T]; observer: Observer[T]):
                                                                          Disposable[T] =
  result = new Disposable[T]
  result.observable = observable
  result.observer = observer

proc dispose*[T](self: Disposable[T]) =
  if self.disposed or self.observable.observers.len == 0: return

  for i, obs in self.observable.observers:
    if obs == self.observer:
      self.observable.observers.del(i)
      break

  self.disposed = true

## *Observer ============================================================================
proc newObserver*[T](onNext: fn[T]; onError: fe = doNothing[Error];
    onCompleted: fc = doNothing): Observer[T] =
  Observer[T](onNext: onNext, onError: onError, onCompleted: onCompleted)

## *Observable ==========================================================================
proc newObservable*[T](onSubscribe: fn[Observer[T]]): Observable[T] =
  Observable[T](observers: newSeq[Observer[T]](), onSubscribe: onSubscribe)
proc newObservable*[T](): Observable[T] =
  newObservable[T](doNothing[Observer[T]])

proc subscribe*[T](self: Observable[T]; observer: Observer[T]): Disposable[T] =
  self.observers.add(observer)
  self.onSubscribe(observer)
  newDisposable[T](self, observer)

template subscribe*[T](self: Observable[T]; onNext: fn[T];
    onError: fe = doNothing[Error]; onCompleted: fc = doNothing): Disposable[T] =
  self.subscribe(newObserver(onNext, onError, onCompleted))

template subscribeBlock*(self: Observable[Unit]; action: untyped): Disposable[Unit] =
  self.subscribe(onNext = proc(_: Unit) =
    action
  )

