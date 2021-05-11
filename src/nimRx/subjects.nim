import sugar, sequtils
import nimRx/[core]

proc doNothing[T](v: T): void = discard
proc doNothing(): void = discard
## *Subject =============================================================================
type
  Subject*[T] = ref object of RootObj
    ober: Observer[T]
    oble: Observable[T]

proc asObservable*[T](self: Subject[T]): Observable[T] = self.oble

proc newSubject*[T](): Subject[T] =
  let subject = Subject[T]()
  subject.oble = newObservable[T]()
  subject.oble.setOnSubscribe proc(o: Observer[T]): IDisposable =
    if subject.oble.isCompleted:
      subject.oble.execOnCompleted()
    newSubscription(subject.oble.asObservable, o).asDisposable()
  subject.ober = newObserver[T](
    (proc(v: T): void =
      if subject.oble.isCompleted: return
      subject.oble.execOnNext(v)
    ),
    (proc(e: Error): void =
      if subject.oble.isCompleted: return
      var s = subject.oble.observers
      subject.oble.observers.setLen(0)
      s.apply((x: Observer[T]) => x.onError(e))
    ),
    (proc(): void =
      subject.oble.execOnCompleted()
      subject.oble.observers.setLen(0)
      subject.oble.setAsCompleted()
    ),
  )
  return subject

template onNext*[T](subject: Subject[T]; v: T): void =
  subject.ober.onNext(v)
template onError*[T](subject: Subject[T]; e: Error): void =
  subject.ober.onError(e)
template onCompleted*[T](subject: Subject[T]): void =
  subject.ober.onCompleted()

template onNext*(subject: Subject[Unit]): void =
  subject.onNext(unitDefault())

template subscribe*[T](self: Subject[T]; observer: Observer[T]): IDisposable =
  self.oble.subscribe(observer)
template subscribe*[T](self: Subject[T];
    onNext: (T)->void;
    onError: (Error)->void = doNothing[Error];
    onCompleted: ()->void = doNothing):
        IDisposable =
  self.observable.subscribe(onNext, onError, onCompleted)

template subscribeBlock*(self: Subject[Unit]; action: untyped): IDisposable =
  self.subscribe(proc(_: Unit) =
    action
  )

