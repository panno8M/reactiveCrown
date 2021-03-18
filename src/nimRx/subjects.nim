import nimRx/[core, gameObject]

type
  fn[T] = proc(v: T): void
  fe = proc(e: Error): void
  fc = proc(): void
proc doNothing[T](v: T): void = discard
proc doNothing(): void = discard
## *Subject =============================================================================
type
  Subject*[T] = ref object of gameObject
    observer*: Observer[T]
    observable*: Observable[T]

proc newSubject*[T](): Subject[T] =
  let subject = Subject[T](observable: newObservable[T]())
  subject.observable = newObservable[T](
    proc(observer: Observer[T]): void =
    if subject.observable.completed:
      for obs in subject.observable.observers: obs.onCompleted())
  subject.observer = newObserver[T](
    (proc(v: T): void =
      if subject.observable.completed: return
      for obs in subject.observable.observers: obs.onNext(v)),
    (proc(e: Error): void =
      if subject.observable.completed: return
      var s = newSeq[Observer[T]](subject.observable.observers.len)
      for i, v in subject.observable.observers: s[i] = v
      subject.observable.observers.setLen(0)
      for obs in s: obs.onError(e)),
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

template subscribe*[T](self: Subject[T]; observer: Observer[T]): Disposable[T] =
  self.observable.subscribe(observer)
template subscribe*[T](self: Subject[T]; onNext: fn[T];
    onError: fe = doNothing[Error]; onCompleted: fc = doNothing): Disposable[T] =
  self.observable.subscribe(onNext, onError, onCompleted)

