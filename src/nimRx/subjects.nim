import sugar, sequtils
import nimRx/[core]

proc doNothing[T](v: T): void = discard
proc doNothing(): void = discard
## *Subject =============================================================================
type
  Subject*[T] = ref object of RootObj
    observer: Observer[T]
    observable: Observable[T]

proc asObservable*[T](self: Subject[T]): Observable[T] = self.observable

proc newSubject*[T](): Subject[T] =
  let subject = Subject[T]()
  subject.observable = newObservable[T]()
  subject.observable.setOnSubscribe proc(o: Observer[T]): IDisposable =
    if subject.observable.isCompleted:
      subject.observable.execOnCompleted()
    newDisposable(subject.observable, o).toDisposable()
  subject.observer = newObserver[T](
    (proc(v: T): void =
      if subject.observable.isCompleted: return
      subject.observable.execOnNext(v)
    ),
    (proc(e: Error): void =
      if subject.observable.isCompleted: return
      var s = subject.observable.observers
      subject.observable.observers.setLen(0)
      s.apply((x: Observer[T]) => x.onError(e))
    ),
    (proc(): void =
      subject.observable.execOnCompleted()
      subject.observable.observers.setLen(0)
      subject.observable.setAsCompleted()
    ),
  )
  return subject

template onNext*[T](subject: Subject[T]; v: T): void =
  subject.observer.onNext(v)
template onError*[T](subject: Subject[T]; e: Error): void =
  subject.observer.onError(e)
template onCompleted*[T](subject: Subject[T]): void =
  subject.observer.onCompleted()

template onNext*(subject: Subject[Unit]): void =
  subject.onNext(unitDefault())

template subscribe*[T](self: Subject[T]; observer: Observer[T]): IDisposable =
  self.observable.subscribe(observer)
template subscribe*[T](self: Subject[T];
    onNext: (T)->void;
    onError: (Error)->void = doNothing[Error];
    onCompleted: ()->void = doNothing):
        IDisposable =
  self.observable.subscribe(onNext, onError, onCompleted)

template subscribeBlock*(self: Subject[Unit]; action: untyped): Disposable[Unit] =
  self.subscribe(proc(_: Unit) =
    action
  )

