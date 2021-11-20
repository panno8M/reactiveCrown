import sugar
import sequtils

# rx
import core

# Subject =============================================================================
type
  Subject*[T] = ref object
    ober: Observer[T]
    observable: Observable[T]
    observers: seq[Observer[T]]
    isCompleted: bool

converter toObservable*[T](self: Subject[T]): Observable[T] = self.observable
template `<>`*[T](self: Subject[T]): Observable[T] = self.toObservable

converter toObserver*[T](self: Subject[T]): Observer[T] = self.ober

template execOnNext[T](self: Subject[T]; v: T) =
  if self.toObservable.hasAnyObservers():
    self.observers.apply((it: Observer[T]) => it.onNext(v))
# template execOnError[T](self: Subject[T]; e: Error) =
#   if self.toObservable.hasAnyObservers():
#     self.observers.apply((it: Observer[T]) => it.onError(e))
template execOnComplete[T](self: Subject[T]) =
  if self.toObservable.hasAnyObservers():
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
      subject.execOnComplete()
    newSubscription(subject, ober)
  subject.ober = Observer[T](
    onNext: (proc(v: T): void =
      if subject.isCompleted: return
      subject.execOnNext(v)
    ),
    onError: (proc(e: ref Exception): void =
      if subject.isCompleted: return
      var s = subject.observers
      subject.observers.setLen(0)
      s.apply((x: Observer[T]) => x.onError(e))
    ),
    onComplete: (proc(): void =
      subject.execOnComplete()
      subject.observers.setLen(0)
      subject.isCompleted = true
    ),
  )
  return subject
