import sugar

type
  Observer*[T] = ref object
    onNext*: (T)->void
    onError*: (ref Exception)->void
    onComplete*: ()->void
  Observable*[T] = ref object
    onSubscribe*: Observer[T]->Disposable
    hasAnyObservers*: ()->bool
    removeObserver*: (Observer[T])->void
  Disposable* = ref object
    dispose*: ()->void
  Subscription[T] = ref object
    disposable: Disposable
    observable: Observable[T]
    observer: Observer[T]
    isDisposed: bool


# Subscription ==========================================================================
converter `toDisposable`*[T](subscription: Subscription[T]): Disposable =
  subscription.disposable

proc newSubscription*[T](oble: Observable[T]; ober: Observer[T]): Subscription[T] =
  var sbsc = Subscription[T]( observable: oble, observer: ober )
  sbsc.disposable = Disposable(dispose: proc() =
    if sbsc.isDisposed or not sbsc.observable.hasAnyObservers():
      return
    sbsc.observable.removeObserver(sbsc.observer)
    sbsc.isDisposed = true
  )
  return sbsc

# Observer ============================================================================
proc newObserver*[T](
      onNext: proc(v: T);
      onError: proc(e: ref Exception) = nil;
      onComplete: proc() = nil;
    ): Observer[T] =
  Observer[T](
    onNext: onNext,
    onError: (if onError != nil: onError else: (e: ref Exception)=>(discard)),
    onComplete: (if onComplete != nil: onComplete else: ()=>(discard)),
  )

# Observable ==========================================================================
proc newObservable*[T](onSubscribe: (Observer[T])->Disposable): Observable[T] =
  Observable[T](onSubscribe: onSubscribe)

proc subscribe*[T](self: Observable[T]; observer: Observer[T]): Disposable =
  self.onSubscribe(observer)
template subscribe*[T](self: Observable[T];
      onNext: proc(v: T);
      onError: proc(e: ref Exception) = nil;
      onComplete: proc() = nil;
    ): Disposable =
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
