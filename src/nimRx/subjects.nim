import sugar, sequtils
import nimRx/[core]

## *Subject =============================================================================
type
  Subject*[T] = ref object of RootObj
    ober: Observer[T]
    iObservable: IObservable[T]
    observers: seq[Observer[T]]
    isCompleted: bool

proc asObservable*[T](self: Subject[T]): IObservable[T] = self.iObservable

template execOnNext[T](self: Subject[T]; v: T) =
  if self.asObservable.hasAnyObservers():
    self.observers.apply((it: Observer[T]) => it.onNext(v))
# template execOnError[T](self: Subject[T]; e: Error) =
#   if self.asObservable.hasAnyObservers():
#     self.observers.apply((it: Observer[T]) => it.onError(e))
template execOnCompleted[T](self: Subject[T]) =
  if self.asObservable.hasAnyObservers():
    self.observers.apply((it: Observer[T]) => it.onCompleted())

proc addObserver[T](self: Subject[T]; ober: Observer[T]) =
  self.observers.add ober

proc newSubject*[T](): Subject[T] =
  let subject = Subject[T](
    observers: newSeq[Observer[T]](),
  )
  subject.iObservable = IObservable[T](
    hasAnyObservers: () => subject.observers.len != 0,
    removeObserver: (o: Observer[T]) => subject.observers.keepIf(v => v != o),
  )
  subject.iObservable.setOnSubscribe proc(ober: Observer[T]): IDisposable =
    subject.addobserver ober
    if subject.isCompleted:
      subject.execOnCompleted()
    newSubscription(subject.asObservable, ober).asDisposable()
  subject.ober = newObserver[T](
    (proc(v: T): void =
      if subject.isCompleted: return
      subject.execOnNext(v)
    ),
    (proc(e: Error): void =
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
template onError*[T](subject: Subject[T]; e: Error): void =
  subject.ober.onError(e)
template onCompleted*[T](subject: Subject[T]): void =
  subject.ober.onCompleted()

