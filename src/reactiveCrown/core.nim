{.deadCodeElim.}
{.experimental: "strictFuncs".}
{.experimental: "strictEffects".}
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
    x is X[T]
    x.onSubscribe(ptr Observer[T]) is Disposable
    x.hasAnyObservers() is bool
    x.removeObserver(ptr Observer[T])

# {.push, raises: [NilAccessDefect].}
func toAbstractObserver*[T](observer: ptr ConceptObserver[T]): Observer[T] =
  if observer.isNil: raise NilAccessDefect.newException("\"observer\" must be not nil")
  Observer[T](
    OnNext: (option proc(x: T) = observer[].onNext x),
    OnError: (option proc(x: ref Exception) = observer[].onError x),
    OnComplete: (option proc() = observer[].onComplete)
  )
func toAbstractObservable*[T](observable: ptr ConceptObservable[T]): Observable[T] =
  if observable.isNil: raise NilAccessDefect.newException("\"observable\" must be not nil")
  {.effects.}
  Observable[T](
    onSubscribe: (proc(x: ptr Observer[T]): Disposable = observable[].onSubscribe x),
    hasAnyObservers: (proc(): bool = observable[].hasAnyObservers),
    removeObserver: (proc(x: ptr Observer[T]) = observable[].removeObserver x)
  )
# {.pop.}

{.push, raises: [].}
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
{.pop.}


# Observer ============================================================================
func newObserver*[T](
      onNext: T->void;
      onError= default(ref Exception->void);
      onComplete= default(()->void);
    ): Observer[T] {.raises: [].} =
  Observer[T](
    OnNext: option(onNext),
    OnError: option(onError),
    OnComplete: option(onComplete),
  )

when isMainModule:
  var x = Observer[int](OnNext: option proc(x: int) {.closure.} = echo(x))
  x.onNext(10)
  dump Observer[int] is ConceptObserver[int]


# Observable ==========================================================================
{.push, raises: [].}
func newObservable*[T](onSubscribe: (Observer[T])->Disposable): Observable[T] =
  Observable[T](onSubscribe: onSubscribe)
func hasAnyObservers*[T](this: Observable[T]): bool {.inline.} = this.hasAnyObservers()


proc subscribe*[T](this: var ConceptObservable[T]; observer: ptr Observer[T]): Disposable {.discardable.} =
  this.onSubscribe(observer)
{.pop.}
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
