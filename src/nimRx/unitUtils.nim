import core
import subjects

type Unit* = ref object

proc unitDefault*(): Unit = new Unit

template subscribeBlock*(self: IObservable[Unit];
    action: untyped): IDisposable =
  self.subscribe(onNext = proc(_: Unit) =
    action
  )

template onNext*(subject: Subject[Unit]): void =
  subject.onNext(unitDefault())
