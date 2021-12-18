{.deadCodeElim.}
{.experimental: "strictFuncs".}
{.experimental: "strictEffects".}
import std/options
import std/sequtils
import std/deques

import core


# Subject ----------------------------------------------------------------------------- #
type
  ConceptSubject*[T] = concept x
    x is ConceptObserver[T]
    x is ConceptObservable[T]

# ----------------------------------------------------------------------------- Subject #
# Publish Subject --------------------------------------------------------------------- #

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
proc onError*[T](this: var PublishSubject[T]; x: ref Exception) =
  if this.stat.isCompleted: return
  if this.stat.error != nil: return
  this.stat.error = x
  if this.hasAnyObservers:
    try:
      for observer in this.observers.mitems: observer[].onError x
    except:
      this.onError getCurrentException()
  this.observers.setLen(0)
proc onNext*[T](this: var PublishSubject[T]; x: T) =
  if this.stat.isCompleted: return
  if this.stat.error != nil: return
  if this.hasAnyObservers:
    try:
      for observer in this.observers.mitems: observer[].onNext x
    except:
      this.onError getCurrentException()
proc onComplete*[T](this: var PublishSubject[T]) =
  if this.stat.isCompleted: return
  if this.stat.error != nil: return
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

# =============
# PublishSubject[int] -?-> ConceptObserver[int]
# PublishSubject[int] -?-> ConceptObservable[int]
# PublishSubject[int] -?-> ConceptSubject[int]

var x = PublishSubject[int]()
discard x.addr.toAbstractObserver()
discard x.addr.toAbstractObservable()
# =============

# ------------------------------------------------------------------------------- Publish Subject #
# Replay Subject -------------------------------------------------------------------------------- #

# type ReplaySubject*[T] {.byref.} = object
#   sbj: Subject[T]
#   bufferSize: Natural
#   cache: Deque[T]

# func asSubject*[T](this: ReplaySubject[T]): lent Subject[T] = this.sbj
# func asSubject*[T](this: var ReplaySubject[T]): var Subject[T] = this.sbj

# proc trim[T](this: var ReplaySubject[T]) =
#   while this.cache.len > this.bufferSize:
#     this.cache.popFirst()


# proc newReplaySubject*[T](bufferSize: Natural = Natural.high): ReplaySubject[T] =
#   var subject = ReplaySubject[T](
#     bufferSize: bufferSize,
#   )

#   subject.sbj.asObservable.onSubscribe = proc(ober: Observer[T]): Disposable =
#     for x in subject.cache.items: ober.next x
#     if subject.sbj.isCompleted:
#       ober.complete
#     elif subject.sbj.getLastError != nil:
#       ober.error subject.sbj.getLastError
#     else:
#       subject.sbj.addobserver ober
#     newSubscription(subject.sbj.asObservable, ober)

#   subject.sbj.asObserver.onNext = some proc(v: T) =
#     subject.cache.addLast v
#     if subject.sbj.hasAnyObservers:
#       for observer in subject.sbj.observers.mitems: observer.next v
#     subject.trim

#   subject.sbj.asObserver.onError = some proc(e: ref Exception) =
#     subject.sbj.stat.error = e
#     if subject.sbj.hasAnyObservers:
#       for observer in subject.sbj.observers.mitems: observer.error e
#     subject.asSubject.observers.setLen(0)
#     reset subject.sbj.ober

#   subject.sbj.asObserver.onComplete = some proc() =
#     subject.sbj.stat.isCompleted = true
#     if subject.sbj.hasAnyObservers:
#       for observer in subject.sbj.observers.mitems: observer.complete
#     subject.sbj.observers.setLen(0)
#     reset subject.sbj.ober

#   return subject

# # Operator Subject --------------------------------------------------------------------- #

# type OperatorSubject*[T] {.byref.} = object
#   sbj: Subject[T]

# func asSubject*[T](this: OperatorSubject[T]): lent Subject[T] = this.sbj
# func asSubject*[T](this: var OperatorSubject[T]): var Subject[T] = this.sbj

# proc newOperatorSubject*[T](): OperatorSubject[T] =
#   var subject = OperatorSubject[T]()

#   subject.asObservable.onSubscribe = proc(ober: Observer[T]): Disposable =
#     if subject.isCompleted:
#       ober.complete
#     else:
#       subject.addobserver ober
#     newSubscription(subject, ober)

#   subject.asObserver.onNext = some proc(v: T) =
#     subject.execOnNext(v)

#   subject.asObserver.onError = some proc(e: ref Exception) =
#     if not subject.asObservable.hasAnyObservers(): return
#     var s = subject.asSubject.observers
#     subject.asSubject.observers.setLen(0)
#     for observer in s: observer.error(e)

#   subject.asObserver.onComplete = some proc() =
#     subject.asSubject.stat.isCompleted = true
#     subject.execOnComplete()
#     subject.asSubject.observers.setLen(0)
#     reset subject.asSubject.ober[]

#   return subject

# # ------------------------------------------------------------------------------- Operator Subject #