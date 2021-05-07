import sugar, sequtils
import nimRx/[core]

proc doNothing[T](v: T): void = discard
proc doNothing(): void = discard
## *Subject =============================================================================
type
  Subject*[T] = ref object of RootObj
    observer*: Observer[T]
    observable*: Observable[T]

proc newSubject*[T](): Subject[T] =
  let subject = Subject[T](observable: newObservable[T]())
  subject.observable = newObservable[T](proc(observer: Observer[T]) =
    if subject.observable.completed:
      for obs in subject.observable.observers: obs.onCompleted())
  subject.observer = newObserver[T](
    (proc(v: T): void =
      if subject.observable.completed: return
      for obs in subject.observable.observers: obs.onNext(v)),
    (proc(e: Error): void =
      if subject.observable.completed: return
      var s = subject.observable.observers
      subject.observable.observers.setLen(0)
      s.apply((x: Observer[T]) => x.onError(e))
    ),
    (proc(): void =
      for obs in subject.observable.observers: obs.onCompleted()
      subject.observable.observers.setLen(0)
      subject.observable.completed = true))
  return subject

template onNext*[T](subject: Subject[T]; v: T): void =
  subject.observer.onNext(v)
template onError*[T](subject: Subject[T]; e: Error): void =
  subject.observer.onError(e)
template onCompleted*[T](subject: Subject[T]): void =
  subject.observer.onCompleted()

template onNext*(subject: Subject[Unit]): void =
  subject.onNext(unitDefault())

proc subscribe*[T](self: Subject[T]; observer: Observer[T]): Disposable[T] =
  self.observable.subscribe(observer)
proc subscribe*[T](self: Subject[T];
    onNext: (T)->void;
    onError: (Error)->void = doNothing[Error];
    onCompleted: ()->void = doNothing):
        Disposable[T] =
  self.observable.subscribe(onNext, onError, onCompleted)

template subscribeBlock*(self: Subject[Unit]; action: untyped): Disposable[Unit] =
  self.subscribe(proc(_: Unit) =
    action
  )

