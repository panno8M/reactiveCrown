##[
  ReactiveX implemented with Nim.

  Simple Usage
  ============
]##

runnableExamples:
  # import rx/[core, operators, subjects] # It is the same as.

  import rx/unitUtils
  import sugar
  import times

  # procs just for example
  proc focus() = return
  proc jumpTo() = return
  var onButtonClicked: proc()
  # ======================

  const doubleClickBorder_sec = 0.01'f

  let
    sbjOnBtnClicked = newSubject[Unit]()

    dspOnBtnClicked =
      sbjOnBtnClicked.asObservable
        .doThat((_: Unit) => echo "\"Button\" has clicked!")
        .subscribeBlock:
          focus()

    obsOnBtnDoubleClicked =
      sbjOnBtnClicked.asObservable
        .map(_ => cpuTime())
        .buffer(2, 1)
        .filter(seqt => seqt.len == 2)
        .map(seqt => seqt[1]-seqt[0])
        .filter(dt => dt <= doubleClickBorder_sec)
        .doThat((dt: float) => echo "\"Button\" has double clicked!")

    dspOnBtnDoubleClicked =
      obsOnBtnDoubleClicked
        .subscribe(
          (proc(dt: float) =

            # some processing...

            jumpTo()
          ),
        )

  onButtonClicked = proc() =
    sbjOnBtnClicked.onNext()

##[
  Modules
  =======

  [core](rx/core.html)
  -----------------------

  | It is the core of this library.
  | It is useless by itself basically but, it is necessary to use rx.
  | It will be implicitly imported by written "import rx" .

  [subjects](rx/subjects.html)
  -------------------------------

  It will be implicitly imported by written "import rx" .

  [operators](rx/operators.html)
  ---------------------------------

  It will be implicitly imported by written "import rx" .

  [unitUtils](rx/unitUtils.html)
  ---------------------------------

  To use this module, you need to explicitly import it by writing "import rx/unitUtils".

]##

import rx/[core, subjects, operators]
export core, subjects, operators

# Imported to generate the document of unitUtils by "nim doc --project" command.
import rx/unitUtils
