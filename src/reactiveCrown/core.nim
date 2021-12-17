import std/options
import std/sugar
import std/typetraits

import tickets
export tickets

# template `-?->`*(Type, Concept: typedesc): untyped =
#   when Type is not Concept:
#     {.error: $Type & " cannot raise to " & $Concept.}

type
  Observer*[T] {.byref.} = object
    OnNext*: Option[T->void]
    OnError*: Option[ref Exception->void]
    OnComplete*: Option[()->void]
  Observable*[T] {.byref.} = object
    onSubscribe*: ptr Observer[T]->Disposable
    hasAnyObservers*: ()->bool
    removeObserver*: ptr Observer[T]->void
  Disposable* = DisposableTicket[void]

  ConceptObserver*[T] = concept var x
    type X = genericHead typeof x
    x is X[T]
    x.onNext(T)
    x.onError(ref Exception)
    x.onComplete()
  ConceptObservable*[T] = concept var x
    type X = genericHead typeof x
    type ptrx = ptr typeof(x)
    x is X[T]
    x.onSubscribe(ptr Observer[T]) is Disposable
    ptrx.hasAnyObservers() is bool
    ptrx.removeObserver(ptr Observer[T])

proc toAbstractObserver*[T](this: ptr ConceptObserver[T]): Observer[T] =
  Observer[T](
    OnNext: (option proc(x: T) = this[].onNext x),
    OnError: (option proc(x: ref Exception) = this[].onError x),
    OnComplete: (option proc() = this[].onComplete)
  )
proc toAbstractObservable*[T](this: ptr ConceptObservable[T]): Observable[T] =
  Observable[T](
    onSubscribe: (proc(x: ptr Observer[T]): Disposable = this[].onSubscribe x),
    hasAnyObservers: (proc(): bool = this.hasAnyObservers),
    removeObserver: (proc(x: ptr Observer[T]) = this.removeObserver x)
  )

proc onError*[T](observer: var Observer[T]; x: ref Exception) =
  try:
    if observer.OnError.isSome: observer.OnError.get()(x)
  except:
    observer.onError getCurrentException()
proc onNext*[T](observer: var Observer[T]; x: T) =
  try:
    if observer.OnNext.isSome: observer.OnNext.get()(x)
  except:
    observer.onError getCurrentException()
proc onComplete*[T](observer: var Observer[T]) =
  try:
    if observer.OnComplete.isSome: observer.OnComplete.get()()
  except:
    observer.onError getCurrentException()


# Observer ============================================================================
proc newObserver*[T](
      onNext: T->void;
      onError= default(ref Exception->void);
      onComplete= default(()->void);
    ): Observer[T] =
  Observer[T](
    OnNext: option(onNext),
    OnError: option(onError),
    OnComplete: option(onComplete),
  )

# proc error*[T](this: var ConceptObserver[T]; x: ref Exception) =
#   try:
#     this.onError x
#   except:
#     this.error x
# proc next*[T](this: var ConceptObserver[T]; x: T; xs: varargs[T]) =
#   try:
#     this.onNext x
#     for x in xs: this.onNext x
#   except:
#     this.error getCurrentException()
# proc complete*[T](this: var ConceptObserver[T]) =
#   try:
#     this.onComplete
#   except:
#     this.error getCurrentException()


when isMainModule:
  var x = Observer[int](OnNext: option proc(x: int) {.closure.} = echo(x))
  x.onNext(10)
  dump Observer[int] is ConceptObserver[int]


# Observable ==========================================================================
proc newObservable*[T](onSubscribe: (Observer[T])->Disposable): Observable[T] =
  Observable[T](onSubscribe: onSubscribe)
proc hasAnyObservers*[T](this: Observable[T]): bool {.inline.} = this.hasAnyObservers()


proc subscribe*[T](this: var ConceptObservable[T]; observer: ptr Observer[T]): Disposable {.discardable.} =
  this.onSubscribe(observer)
template subscribe*[T](this: var ConceptObservable[T];
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
  var observer = newObserver(onNext, onError, onComplete)
  this.subscribe(observer.addr)
