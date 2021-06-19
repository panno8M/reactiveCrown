import sugar

type
  # TODO: define error type
  Error* = ref object
    msg: string

  Observer*[T] = ref object
    onNext*: (T)->void
    onError*: (Error)->void
    onComplete*: ()->void
  IObservable*[T] = ref object
    onSubscribe*: Observer[T]->IDisposable
    hasAnyObservers*: ()->bool
    removeObserver*: (Observer[T])->void
  IDisposable* = ref object
    dispose*: ()->void
  Subscription[T] = ref object
    iDisposable: IDisposable
    iObservable: IObservable[T]
    observer: Observer[T]
    isDisposed: bool

proc newError*(msg: string): Error = Error(msg: msg)
proc `$`*(e: Error): string = e.msg

# Subscription ==========================================================================
proc newSubscription*[T](iObservable: IObservable[T]; observer: Observer[T]):
                                                                  IDisposable =
  let subscription = Subscription[T](
    iObservable: iObservable,
    observer: observer,
  )
  subscription.iDisposable = IDisposable(dispose: proc(): void =
    if subscription.isDisposed or not subscription.iObservable.hasAnyObservers():
      return
    subscription.iObservable.removeObserver(subscription.observer)
    subscription.isDisposed = true
  )
  return subscription.iDisposable

# Observer ============================================================================
proc newObserver*[T](
      onNext: proc(v: T);
      onError: proc(e: Error) = nil;
      onComplete: proc() = nil;
    ): Observer[T] =
  Observer[T](
    onNext: onNext,
    onError: (if onError != nil: onError else: (e: Error)=>(discard)),
    onComplete: (if onComplete != nil: onComplete else: ()=>(discard)),
  )

# Observable ==========================================================================
proc newIObservable*[T](onSubscribe: (Observer[T])->IDisposable): IObservable[T] =
  IObservable[T](onSubscribe: onSubscribe)

proc subscribe*[T](self: IObservable[T]; observer: Observer[T]): IDisposable =
  self.onSubscribe(observer)
template subscribe*[T](self: IObservable[T];
      onNext: proc(v: T);
      onError: proc(e: Error) = nil;
      onComplete: proc() = nil;
    ): IDisposable =
  ## Using this, you can omit the upper code as the lower one.
  ##
  ## .. code-block:: Nim
  ##    discard someObservable
  ##      .subscribe(newObserver(
  ##        (v: T) => onNext(v),
  ##        (e: Error) => onError(e),
  ##        () => onComplete()
  ##      ))
  ##
  ## .. code-block:: Nim
  ##    discard someObservable
  ##      .subscribe(
  ##        (v: T) => onNext(v),
  ##        (e: Error) => onError(e),
  ##        () => onComplete()
  ##      )
  self.subscribe(newObserver(onNext, onError, onComplete))
