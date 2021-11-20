import options
import sugar

type
  Observer*[T] = ref object
    onNext: T->void
    onError: Option[ref Exception->void]
    onComplete: Option[()->void]
  Observable*[T] = ref object
    onSubscribe*: Observer[T]->Disposable
    hasAnyObservers*: ()->bool
    removeObserver*: Observer[T]->void
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
      onNext: T->void;
      onError= default(ref Exception->void);
      onComplete= default(()->void);
    ): Observer[T] =
  Observer[T](
    onNext: onNext,
    onError: option(onError),
    onComplete: option(onComplete),
  )

proc onNext*[T](observer: Observer[T]; x: T) {.inline.} = observer.onNext(x)
proc onError*[T](observer: Observer[T]; e: ref Exception) {.inline.} = 
  if observer.onError.isSome: observer.onError.get()(e)
proc onComplete*[T](observer: Observer[T]) {.inline.} =
  if observer.onComplete.isSome: observer.onComplete.get()()

# Observable ==========================================================================
proc newObservable*[T](onSubscribe: (Observer[T])->Disposable): Observable[T] =
  Observable[T](onSubscribe: onSubscribe)

proc subscribe*[T](self: Observable[T]; observer: Observer[T]): Disposable {.discardable.} =
  self.onSubscribe(observer)
template subscribe*[T](self: Observable[T];
      onNext: T->void;
      onError= default(ref Exception->void);
      onComplete= default(()->void);
    ): Disposable =
  ## Using this, you can omit the upper code as the lower one.
  ##
  ## .. code-block:: Nim
  ##    someObservable
  ##      .subscribe(newObserver(
  ##        (v: T) => onNext(v),
  ##        (e: Error) => onError(e),
  ##        () => onComplete()
  ##      ))
  ##
  ## .. code-block:: Nim
  ##    someObservable
  ##      .subscribe(
  ##        (v: T) => onNext(v),
  ##        (e: Error) => onError(e),
  ##        () => onComplete()
  ##      )
  self.subscribe(newObserver(onNext, onError, onComplete))
