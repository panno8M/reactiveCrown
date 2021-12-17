import std/options
import std/sugar

import tickets
export tickets

type
  Observer*[T] {.byref.} = object
    onNext*: Option[T->void]
    onError*: Option[ref Exception->void]
    onComplete*: Option[()->void]
  Observable*[T] {.byref.} = object
    onSubscribe*: Observer[T]->Disposable
    hasAnyObservers*: ()->bool
    removeObserver*: Observer[T]->void
  Disposable* = DisposableTicket[void]
  Subscription[T] = object
    disposable: Disposable
    observable: Observable[T]
    observer: Observer[T]


# Subscription ==========================================================================
converter `toDisposable`*[T](subscription: Subscription[T]): lent Disposable =
  subscription.disposable

proc newSubscription*[T](oble: Observable[T]; ober: Observer[T]): Subscription[T] =
  var sbsc = Subscription[T]( observable: oble, observer: ober )
  sbsc.disposable = Disposable.issue:
    if sbsc.observable.hasAnyObservers():
      sbsc.observable.removeObserver(sbsc.observer)
  return sbsc

# Observer ============================================================================
proc newObserver*[T](
      onNext: T->void;
      onError= default(ref Exception->void);
      onComplete= default(()->void);
    ): Observer[T] =
  Observer[T](
    onNext: option(onNext),
    onError: option(onError),
    onComplete: option(onComplete),
  )

# proc next*[T](observer: Observer[T]; x: T) {.inline.} =
#   try:
#     if observer.onNext.isSome: observer.onNext.get()(x)
#   except:
#     observer.error getCurrentException()

proc next*[T](observer: Observer[T]; x: T; xs: varargs[T]) {.inline.} =
  try:
    if observer.onNext.isSome: observer.onNext.get()(x)
  except:
    observer.error getCurrentException()
  for x in xs:
    try:
      if observer.onNext.isSome: observer.onNext.get()(x)
    except:
      observer.error getCurrentException()

proc error*[T](observer: Observer[T]; e: ref Exception) {.inline.} =
  try:
    if observer.onError.isSome: observer.onError.get()(e)
  except:
    observer.error getCurrentException()

proc complete*[T](observer: Observer[T]) {.inline.} =
  try:
    if observer.onComplete.isSome: observer.onComplete.get()()
  except:
    observer.error getCurrentException()

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

proc hasAnyObservers*[T](this: Observable[T]): bool {.inline.} = this.hasAnyObservers()