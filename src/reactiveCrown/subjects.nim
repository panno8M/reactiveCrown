import std/sugar
import std/options
import std/sequtils
import std/deques
import std/typetraits

import core


type
  ConceptObserver*[T] = concept x
    x.onNext(T)
    x.onError(ref Exception)
    x.onComplete()
  ConceptObservable*[T] = concept x
    type X = genericHead typeof x
    type ptrx = ptr typeof(x)
    x is X[T]
    x.onSubscribe(Observer[T]) is Disposable
    ptrx.hasAnyObservers() is bool
    ptrx.removeObserver(Observer[T])
  ConceptSubject*[T] = concept x
    x is ConceptObserver[T]
    x is ConceptObservable[T]

proc toAbstractObserver*[T](this: ptr ConceptObserver[T]): Observer[T] =
  Observer[T](
    onNext: (option proc(x: T) = this[].onNext x),
    onError: (option proc(x: ref Exception) = this[].onError x),
    onComplete: (option proc() = this[].onComplete)
  )
# proc toAbstractObservable*[T](this: var ConceptObservable[T]): Observable[T] =
#   Observable[T](
#     onSubscribe: (proc(x: Observer[T]): Disposable = this.onSubscribe x),
#   )

proc error*[T](this: var ConceptObserver[T]; x: ref Exception) =
  try:
    this.onError x
  except:
    this.error getCurrentException()
proc next*[T](this: var ConceptObserver[T]; x: T; xs: varargs[T]) =
  try:
    this.onNext x
    for x in xs: this.onNext x
  except:
    this.error getCurrentException()
proc complete*[T](this: var ConceptObserver[T]) =
  try:
    this.onComplete
  except:
    this.error getCurrentException()

proc subscribe*[T](this: var ConceptObservable[T]; observer: Observer[T]): Disposable {.discardable.} =
  this.onSubscribe(observer)
proc subscribe*[T](this: var ConceptObservable[T];
      onNext: T->void;
      onError= default(ref Exception->void);
      onComplete= default(()->void);
    ): Disposable {.discardable.} =
  this.subscribe(newObserver(onNext, onError, onComplete))

# Subject ----------------------------------------------------------------------------- #
type
  Subject*[T] {.byref.} = object
    ober: Observer[T]
    observable: Observable[T]
    observers: seq[Observer[T]]
    stat: tuple[
      isCompleted: bool,
      error: ref Exception ]

func asObservable*[T](this: Subject[T]): lent Observable[T] = this.observable
func asObservable*[T](this: var Subject[T]): var Observable[T] = this.observable
template `<>`*[T](this: Subject[T]): Observable[T] = this.asObservable

func asObserver*[T](this: Subject[T]): lent Observer[T] = this.ober
func asObserver*[T](this: var Subject[T]): var Observer[T] = this.ober

func isCompleted*[T](this: Subject[T]): bool {.inline.} = this.stat.isCompleted
func getLastError*[T](this: Subject[T]): ref Exception {.inline.} = this.stat.error

proc addObserver[T](this: var Subject[T]; ober: Observer[T]) =
  this.observers.add ober

proc hasAnyObservers*[T](subject: Subject[T]): bool =
  subject.observers.len != 0
proc removeObserver*[T](subject: Subject[T]; observer: Observer[T]) =
  subject.observers.keepIf(v => v != observer)

template next*[T](this: Subject[T]; x: T; xs: varargs[T]): untyped =
  this.asObserver.next(x, xs)
template error*[T](this: Subject[T]; args: ref Exception): untyped =
  this.asObserver.error(args)
template complete*[T](this: Subject[T]): untyped =
  this.asObserver.complete()

# ----------------------------------------------------------------------------- Subject #
# Publish Subject --------------------------------------------------------------------- #

type PublishSubject*[T] {.byref.} = object
  observers: seq[Observer[T]]
  stat: tuple[
    isCompleted: bool,
    error: ref Exception ]

func isCompleted*[T](this: var PublishSubject[T]): bool {.inline.} = this.stat.isCompleted
func getLastError*[T](this: var PublishSubject[T]): ref Exception {.inline.} = this.stat.error
proc addObserver[T](this: var PublishSubject[T]; ober: Observer[T]) =
  this.observers.add ober

proc hasAnyObservers*[T](this: ptr PublishSubject[T]): bool =
  this[].observers.len != 0
proc removeObserver*[T](this: ptr PublishSubject[T]; observer: Observer[T]) =
  this[].observers.keepIf(v => v != observer)
proc onSubscribe*[T](this: var PublishSubject[T]; observer: Observer[T]): Disposable =
  if this.isCompleted:
    observer.complete
  elif this.getLastError != nil:
    observer.error this.getLastError
  else:
    this.addobserver observer
  var ptrthis = addr this
  Disposable.issue:
    if ptrthis.hasAnyObservers:
      ptrthis.removeObserver observer

proc onNext*[T](this: var PublishSubject[T]; x: T) =
  if this.stat.isCompleted: return
  if this.stat.error != nil: return
  if this.addr.hasAnyObservers:
    for observer in this.observers.mitems: observer.next x
proc onError*[T](this: var PublishSubject[T]; x: ref Exception) =
  if this.stat.isCompleted: return
  if this.stat.error != nil: return
  this.stat.error = x
  if this.addr.hasAnyObservers:
    for observer in this.observers.mitems: observer.error x
  this.observers.setLen(0)
proc onComplete*[T](this: var PublishSubject[T]) =
  if this.stat.isCompleted: return
  if this.stat.error != nil: return
  this.stat.isCompleted = true
  if this.addr.hasAnyObservers:
    for observer in this.observers.mitems: observer.complete
  this.observers.setLen(0)

# =============
when PublishSubject[int] is not ConceptObserver[int]:
  {.error: "failed!".}
when PublishSubject[int] is not ConceptObservable[int]:
  {.error: "failed!".}
when PublishSubject[int] is not ConceptSubject[int]:
  {.error: "failed!".}

var x = PublishSubject[int]()
discard x.addr.toAbstractObserver
discard x.addr.hasAnyObservers()
# =============

# ------------------------------------------------------------------------------- Publish Subject #
# Replay Subject -------------------------------------------------------------------------------- #

type ReplaySubject*[T] {.byref.} = object
  sbj: Subject[T]
  bufferSize: Natural
  cache: Deque[T]

func asSubject*[T](this: ReplaySubject[T]): lent Subject[T] = this.sbj
func asSubject*[T](this: var ReplaySubject[T]): var Subject[T] = this.sbj

proc trim[T](this: var ReplaySubject[T]) =
  while this.cache.len > this.bufferSize:
    this.cache.popFirst()


proc newReplaySubject*[T](bufferSize: Natural = Natural.high): ReplaySubject[T] =
  var subject = ReplaySubject[T](
    bufferSize: bufferSize,
  )

  subject.sbj.asObservable.onSubscribe = proc(ober: Observer[T]): Disposable =
    for x in subject.cache.items: ober.next x
    if subject.sbj.isCompleted:
      ober.complete
    elif subject.sbj.getLastError != nil:
      ober.error subject.sbj.getLastError
    else:
      subject.sbj.addobserver ober
    newSubscription(subject.sbj.asObservable, ober)

  subject.sbj.asObserver.onNext = some proc(v: T) =
    subject.cache.addLast v
    if subject.sbj.hasAnyObservers:
      for observer in subject.sbj.observers.mitems: observer.next v
    subject.trim

  subject.sbj.asObserver.onError = some proc(e: ref Exception) =
    subject.sbj.stat.error = e
    if subject.sbj.hasAnyObservers:
      for observer in subject.sbj.observers.mitems: observer.error e
    subject.asSubject.observers.setLen(0)
    reset subject.sbj.ober

  subject.sbj.asObserver.onComplete = some proc() =
    subject.sbj.stat.isCompleted = true
    if subject.sbj.hasAnyObservers:
      for observer in subject.sbj.observers.mitems: observer.complete
    subject.sbj.observers.setLen(0)
    reset subject.sbj.ober

  return subject

# Operator Subject --------------------------------------------------------------------- #

type OperatorSubject*[T] {.byref.} = object
  sbj: Subject[T]

func asSubject*[T](this: OperatorSubject[T]): lent Subject[T] = this.sbj
func asSubject*[T](this: var OperatorSubject[T]): var Subject[T] = this.sbj

proc newOperatorSubject*[T](): OperatorSubject[T] =
  var subject = OperatorSubject[T]()

  subject.asObservable.onSubscribe = proc(ober: Observer[T]): Disposable =
    if subject.isCompleted:
      ober.complete
    else:
      subject.addobserver ober
    newSubscription(subject, ober)

  subject.asObserver.onNext = some proc(v: T) =
    subject.execOnNext(v)

  subject.asObserver.onError = some proc(e: ref Exception) =
    if not subject.asObservable.hasAnyObservers(): return
    var s = subject.asSubject.observers
    subject.asSubject.observers.setLen(0)
    for observer in s: observer.error(e)

  subject.asObserver.onComplete = some proc() =
    subject.asSubject.stat.isCompleted = true
    subject.execOnComplete()
    subject.asSubject.observers.setLen(0)
    reset subject.asSubject.ober[]

  return subject

# ------------------------------------------------------------------------------- Operator Subject #