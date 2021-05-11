import sugar, sequtils

type
  Unit* = ref object
  # TODO: define error type
  Error* = ref object
    msg: string

  Observer*[T] = ref object of RootObj
    onNext*: (T)->void
    onError*: (Error)->void
    onCompleted*: ()->void
  Observable*[T] = ref object of RootObj
    observers*: seq[Observer[T]]
    observableFactory: ()->Observable[T]
    onSubscribe*: Observer[T]->IDisposable
    completed: bool
  IDisposable* = object
    dispose*: ()->void
  Disposable*[T] = ref object
    observable: Observable[T]
    observer: Observer[T]
    isDisposed: bool

proc doNothing[T](v: T): void = discard
proc doNothing(): void = discard

proc unitDefault*(): Unit = new Unit

proc newError*(msg: string): Error = Error(msg: msg)
proc `$`*(e: Error): string = e.msg

## *Disposable ==========================================================================
proc newDisposable*[T](observable: Observable[T]; observer: Observer[T]):
                                                                          Disposable[T] =
  result = Disposable[T](observable: observable, observer: observer)

proc toDisposable*[T](self: Disposable[T]): IDisposable =
  var self = self
  IDisposable(dispose: proc(): void =
    if self.isDisposed or self.observable.observers.len == 0:
      return
    self.observable.observers.keepIf(v => v != self.observer)
    self.isDisposed = true
  )

template combineDisposables*(disposables: varargs[IDisposable]): IDisposable =
  IDisposable(dispose: () => disposables.apply(it => it.dispose()))

## *Observer ============================================================================
proc newObserver*[T](onNext: (T)->void;
                     onError: (Error)->void = doNothing[Error];
                     onCompleted: ()->void = doNothing): Observer[T] =
  Observer[T](onNext: onNext, onError: onError, onCompleted: onCompleted)

## *Observable ==========================================================================
proc newObservableFactory*[T](factory: ()->Observable[T]): Observable[T] =
  Observable[T](
    observers: newSeq[Observer[T]](),
    observableFactory: factory,
  )
proc newObservable*[T](): Observable[T] =
  Observable[T](
    observers: newSeq[Observer[T]](),
  )

proc setOnSubscribe*[T](self: Observable[T];
    onSubscribe: Observer[T]->IDisposable) =
  self.onSubscribe = onSubscribe
proc setOnSubscribe*[T](self: Observable[T]; onSubscribe: ()->IDisposable) =
  self.onSubscribe = (o: Observer[T]) => onSubscribe()

proc isCompleted*[T](self: Observable[T]): bool = self.completed
proc setAsCompleted*[T](self: Observable[T]) = self.completed = true


template execOnNext*[T](self: Observable[T]; v: T) =
  self.observers.apply((o: Observer[T]) => o.onNext(v))
template execOnError*[T](self: Observable[T]; e: Error) =
  self.observers.apply((o: Observer[T]) => o.onError(e))
template execOnCompleted*[T](self: Observable[T]) =
  self.observers.apply((o: Observer[T]) => o.onCompleted())
proc mkExecOnNext*[T](self: Observable[T]): (T)->void =
  return proc(v: T) = self.execOnNext(v)
proc mkExecOnError*[T](self: Observable[T]): (Error)->void =
  return proc(e: Error) = self.execOnError(e)
proc mkExecOnCompleted*[T](self: Observable[T]): ()->void =
  return proc() = self.execOnCompleted()


proc addObserver*[T](self: Observable[T]; observer: Observer[T]) =
  self.observers.add(observer)
proc setObserver*[T](self: Observable[T]; observer: Observer[T]) =
  if self.observers.len != 1: self.observers.setLen(1)
  self.observers[0] = observer

proc subscribe*[T](self: Observable[T]; observer: Observer[T]): IDisposable =
  self.addObserver observer

  if self.observableFactory != nil:
    return self.observableFactory().subscribe(observer)
  else:
    return self.onSubscribe(observer)

template subscribe*[T](self: Observable[T];
    onNext: (T)->void;
    onError: (Error)->void = doNothing[Error];
    onCompleted: ()->void = doNothing): IDisposable =
  self.subscribe(newObserver(onNext, onError, onCompleted))

template subscribeBlock*(self: Observable[Unit]; action: untyped): IDisposable =
  self.subscribe(onNext = proc(_: Unit) =
    action
  )

