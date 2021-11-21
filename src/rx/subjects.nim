import sugar
import options
import sequtils
import deques

# rx
import core

# Subject ----------------------------------------------------------------------------- #
type
  Subject*[T] = ref object
    ober: Observer[T]
    observable: Observable[T]
    observers: seq[Observer[T]]
    stat: tuple[
      isCompleted: bool,
      error: ref Exception ]

converter toObservable*[T](this: Subject[T]): Observable[T] = this.observable
template `<>`*[T](this: Subject[T]): Observable[T] = this.toObservable

converter toObserver*[T](this: Subject[T]): Observer[T] = this.ober

func isCompleted*[T](this: Subject[T]): bool {.inline.} = this.stat.isCompleted
func getLastError*[T](this: Subject[T]): ref Exception {.inline.} = this.stat.error

template defineBasicSubjectConverters*(Type: typedesc): untyped =
  converter toSubject*[T](sbj: `Type`[T]): Subject[T] =       sbj.sbj
  converter toObservable*[T](sbj: `Type`[T]): Observable[T] = sbj.sbj
  converter toObserver*[T](sbj: `Type`[T]): Observer[T] =     sbj.sbj

template execOnNext[T](this: Subject[T]; v: T) =
  if this.toObservable.hasAnyObservers():
    for observer in this.observers: observer.next(v)
template execOnError[T](this: Subject[T]; e: ref Exception) =
  if this.toObservable.hasAnyObservers():
    for observer in this.observers: observer.error(e)
template execOnComplete[T](this: Subject[T]): untyped =
  if this.toObservable.hasAnyObservers():
    for observer in this.observers: observer.complete()

proc addObserver[T](this: Subject[T]; ober: Observer[T]) =
  this.observers.add ober

proc newSubject[T](): Subject[T] =
  let subject = Subject[T](
    observers: newSeq[Observer[T]](),
  )
  subject.observable = Observable[T](
    hasAnyObservers: () => subject.observers.len != 0,
    removeObserver: (o: Observer[T]) => subject.observers.keepIf(v => v != o),
  )
  subject.ober = Observer[T]()
  return subject

# ----------------------------------------------------------------------------- Subject #
# Publish Subject --------------------------------------------------------------------- #

type PublishSubject*[T] = ref object
  sbj: Subject[T]

PublishSubject.defineBasicSubjectConverters

proc newPublishSubject*[T](): PublishSubject[T] =
  var subject = PublishSubject[T](sbj: newSubject[T]())

  subject.toObservable.onSubscribe = proc(ober: Observer[T]): Disposable =
    if subject.isCompleted:
      ober.complete()
    elif subject.getLastError != nil:
      ober.error subject.getLastError
    else:
      subject.addobserver ober
    newSubscription(subject, ober)

  subject.toObserver.onNext = some proc(v: T) =
    subject.execOnNext(v)

  subject.toObserver.onError = some proc(e: ref Exception) =
    subject.toSubject.stat.error = e
    if not subject.toObservable.hasAnyObservers(): return
    var s = subject.toSubject.observers
    subject.toSubject.observers.setLen(0)
    for observer in s: observer.error(e)
    reset subject.toSubject.ober[]

  subject.toObserver.onComplete = some proc() =
    subject.toSubject.stat.isCompleted = true
    subject.execOnComplete()
    subject.toSubject.observers.setLen(0)
    reset subject.toSubject.ober[]

  return subject

# ------------------------------------------------------------------------------- Publish Subject #
# Replay Subject -------------------------------------------------------------------------------- #

type ReplaySubject*[T] = ref object
  sbj: Subject[T]
  bufferSize: Natural
  cache: Deque[T]

ReplaySubject.defineBasicSubjectConverters

proc trim[T](this: ReplaySubject[T]) =
  while this.cache.len > this.bufferSize:
    this.cache.popFirst()


proc newReplaySubject*[T](bufferSize: Natural = Natural.high): ReplaySubject[T] =
  var subject = ReplaySubject[T](
    sbj: newSubject[T](),
    bufferSize: bufferSize,
  )

  subject.toObservable.onSubscribe = proc(ober: Observer[T]): Disposable =
    for x in subject.cache.items: ober.next x
    if subject.isCompleted:
      ober.complete()
    elif subject.getLastError != nil:
      ober.error subject.getLastError
    else:
      subject.addobserver ober
    newSubscription(subject, ober)

  subject.toObserver.onNext = some proc(v: T) =
    subject.cache.addLast v
    subject.execOnNext(v)
    subject.trim

  subject.toObserver.onError = some proc(e: ref Exception) =
    subject.toSubject.stat.error = e
    if not subject.toObservable.hasAnyObservers(): return
    var s = subject.toSubject.observers
    subject.toSubject.observers.setLen(0)
    for observer in s: observer.error(e)
    reset subject.toSubject.ober[]

  subject.toObserver.onComplete = some proc() =
    subject.toSubject.stat.isCompleted = true
    subject.execOnComplete()
    subject.toSubject.observers.setLen(0)
    reset subject.toSubject.ober[]

  return subject
