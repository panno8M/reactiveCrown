{.deadCodeElim.}
{.experimental: "strictFuncs".}
{.experimental: "strictEffects".}
import ../core

type
  ConceptSubject*[T] = concept x
    x is ConceptObserver[T]
    x is ConceptObservable[T]