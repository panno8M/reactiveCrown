{.deadCodeElim.}
{.experimental: "strictFuncs".}
{.experimental: "strictEffects".}
import ../core
import subject_concept

type PublishSubject*[T] {.byref.} = object
  observers*: seq[Observer[T]]
  stat: tuple[
    isCompleted: bool,
    error: ref Exception ]

# == API ==
proc onNext*[T](this: var PublishSubject[T]; x: T)
proc onError*[T](this: var PublishSubject[T]; x: ref Exception)
proc onComplete*[T](this: var PublishSubject[T])
proc onSubscribe*[T](this: var PublishSubject[T]; observer: Observer[T]): Disposable

func hasAnyObservers*[T](this: var PublishSubject[T]): bool
proc removeObserver*[T](this: var PublishSubject[T]; observer: Observer[T])

func isCompleted*[T](this: var PublishSubject[T]): bool {.inline.}
func getLastError*[T](this: var PublishSubject[T]): ref Exception {.inline.}
proc addObserver[T](this: var PublishSubject[T]; observer: Observer[T])

func isInvalid*[T](this: var PublishSubject[T]): bool

proc next*[T](this: var PublishSubject[T]; x: T; xs: varargs[T])
proc error*[T](this: var PublishSubject[T]; x: ref Exception)
proc complete*[T](this: var PublishSubject[T])
# == API ==

func isCompleted*[T](this: var PublishSubject[T]): bool {.inline.} = this.stat.isCompleted
func getLastError*[T](this: var PublishSubject[T]): ref Exception {.inline.} = this.stat.error
proc addObserver[T](this: var PublishSubject[T]; observer: Observer[T]) =
  this.observers.add observer

func hasAnyObservers*[T](this: var PublishSubject[T]): bool =
  this.observers.len != 0
proc removeObserver*[T](this: var PublishSubject[T]; observer: Observer[T]) =
  for i in countdown(this.observers.high, 0):
    if this.observers[i] == observer:
      this.observers.delete i
      break
proc onSubscribe*[T](this: var PublishSubject[T]; observer: Observer[T]): Disposable =
  if this.isCompleted:
    observer.onComplete
  elif this.getLastError != nil:
    observer.onError this.getLastError
  else:
    this.addobserver observer
  let ptrthis = addr this
  Disposable.issue:
    ptrthis[].removeObserver observer

{.push, raises: [].}
func isInvalid*[T](this: var PublishSubject[T]): bool =
  this.stat.isCompleted or this.stat.error != nil
proc onNext*[T](this: var PublishSubject[T]; x: T) =
  if this.isInvalid: return
  if this.hasAnyObservers:
    try:
      for observer in this.observers.mitems: observer.onNext x
    except:
      this.onError getCurrentException()
proc onError*[T](this: var PublishSubject[T]; x: ref Exception) =
  if this.isInvalid: return
  this.stat.error = x
  if this.hasAnyObservers:
    try:
      for observer in this.observers.mitems: observer.onError x
    except:
      this.onError getCurrentException()
  this.observers.setLen(0)
proc onComplete*[T](this: var PublishSubject[T]) =
  if this.isInvalid: return
  this.stat.isCompleted = true
  if this.hasAnyObservers:
    try:
      for observer in this.observers.mitems: observer.onComplete
    except:
      this.onError getCurrentException()
  this.observers.setLen(0)
{.pop.}

{.push, raises: [].}
proc next*[T](this: var PublishSubject[T]; x: T; xs: varargs[T]) =
  this.onNext x
  for x in xs: this.onNext x
proc error*[T](this: var PublishSubject[T]; x: ref Exception) =
  this.onError x
proc complete*[T](this: var PublishSubject[T]) =
  this.onComplete
{.pop.}

when isMainModule:
  PublishSubject[int] -?-> ConceptObserver[int]
  PublishSubject[int] -?-> ConceptObservable[int]
  PublishSubject[int] -?-> ConceptSubject[int]

  var x = PublishSubject[int]()
  discard x.addr.toAbstractObserver()
  discard x.addr.toAbstractObservable()