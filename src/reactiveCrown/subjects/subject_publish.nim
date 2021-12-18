{.deadCodeElim.}
{.experimental: "strictFuncs".}
{.experimental: "strictEffects".}
import ../core
import subject_concept

type PublishSubject*[T] {.byref.} = object
  observers: seq[ptr Observer[T]]
  stat: tuple[
    isCompleted: bool,
    error: ref Exception ]

func isCompleted*[T](this: var PublishSubject[T]): bool {.inline.} = this.stat.isCompleted
func getLastError*[T](this: var PublishSubject[T]): ref Exception {.inline.} = this.stat.error
proc addObserver[T](this: var PublishSubject[T]; observer: ptr Observer[T]) =
  this.observers.add observer

func hasAnyObservers*[T](this: var PublishSubject[T]): bool =
  this.observers.len != 0
proc removeObserver*[T](this: var PublishSubject[T]; observer: ptr Observer[T]) =
  for i in countdown(this.observers.high, 0):
    if this.observers[i][] == observer[]:
      this.observers.delete i
      break
proc onSubscribe*[T](this: var PublishSubject[T]; observer: ptr Observer[T]): Disposable =
  if this.isCompleted:
    observer[].onComplete
  elif this.getLastError != nil:
    observer[].onError this.getLastError
  else:
    this.addobserver observer
  let ptrthis = addr this
  Disposable.issue:
    ptrthis[].removeObserver observer

{.push, raises: [].}
func isInvalid*[T](this: var PublishSubject[T]): bool =
  this.stat.isCompleted or this.stat.error != nil
proc onError*[T](this: var PublishSubject[T]; x: ref Exception) =
  if this.isInvalid: return
  this.stat.error = x
  if this.hasAnyObservers:
    try:
      for observer in this.observers.mitems: observer[].onError x
    except:
      this.onError getCurrentException()
  this.observers.setLen(0)
proc onNext*[T](this: var PublishSubject[T]; x: T) =
  if this.isInvalid: return
  if this.hasAnyObservers:
    try:
      for observer in this.observers.mitems: observer[].onNext x
    except:
      this.onError getCurrentException()
proc onComplete*[T](this: var PublishSubject[T]) =
  if this.isInvalid: return
  this.stat.isCompleted = true
  if this.hasAnyObservers:
    try:
      for observer in this.observers.mitems: observer[].onComplete
    except:
      this.onError getCurrentException()
  this.observers.setLen(0)
{.pop.}

{.push, raises: [].}
proc error*[T](this: var PublishSubject[T]; x: ref Exception) =
  this.onError x
proc next*[T](this: var PublishSubject[T]; x: T; xs: varargs[T]) =
  this.onNext x
  for x in xs: this.onNext x
proc complete*[T](this: var PublishSubject[T]) =
  this.onComplete
{.pop.}

when isMainModule:
  # PublishSubject[int] -?-> ConceptObserver[int]
  # PublishSubject[int] -?-> ConceptObservable[int]
  # PublishSubject[int] -?-> ConceptSubject[int]

  var x = PublishSubject[int]()
  discard x.addr.toAbstractObserver()
  discard x.addr.toAbstractObservable()