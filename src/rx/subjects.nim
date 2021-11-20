import sugar
import sequtils

# rx
import core

# Subject =============================================================================
type
  Subject*[T] = ref object of RootObj
    ober: Observer[T]
    observable: Observable[T]
    observers: seq[Observer[T]]
    isCompleted: bool

proc asObservable*[T](self: Subject[T]): Observable[T] = self.observable

template execOnNext[T](self: Subject[T]; v: T) =
  if self.asObservable.hasAnyObservers():
    self.observers.apply((it: Observer[T]) => it.onNext(v))
# template execOnError[T](self: Subject[T]; e: Error) =
#   if self.asObservable.hasAnyObservers():
#     self.observers.apply((it: Observer[T]) => it.onError(e))
template execOnCompleted[T](self: Subject[T]) =
  if self.asObservable.hasAnyObservers():
    self.observers.apply((it: Observer[T]) => it.onComplete())

proc addObserver[T](self: Subject[T]; ober: Observer[T]) =
  self.observers.add ober

proc newSubject*[T](): Subject[T] =
  let subject = Subject[T](
    observers: newSeq[Observer[T]](),
  )
  subject.observable = Observable[T](
    hasAnyObservers: () => subject.observers.len != 0,
    removeObserver: (o: Observer[T]) => subject.observers.keepIf(v => v != o),
  )
  subject.observable.onSubscribe = proc(ober: Observer[T]): Disposable =
    subject.addobserver ober
    if subject.isCompleted:
      subject.execOnCompleted()
    newSubscription(subject.asObservable, ober)
  subject.ober = newObserver[T](
    (proc(v: T): void =
      if subject.isCompleted: return
      subject.execOnNext(v)
    ),
    (proc(e: ref Exception): void =
      if subject.isCompleted: return
      var s = subject.observers
      subject.observers.setLen(0)
      s.apply((x: Observer[T]) => x.onError(e))
    ),
    (proc(): void =
      subject.execOnCompleted()
      subject.observers.setLen(0)
      subject.isCompleted = true
    ),
  )
  return subject

template onNext*[T](subject: Subject[T]; v: T): void =
  subject.ober.onNext(v)
template onError*[T](subject: Subject[T]; e: ref Exception): void =
  subject.ober.onError(e)
template onComplete*[T](subject: Subject[T]): void =
  subject.ober.onComplete()

