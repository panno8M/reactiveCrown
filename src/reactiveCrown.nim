##[
  ReactiveX implemented with Nim.

  Simple Usage
  ============
]##

runnableExamples:
  # import reactiveCrown/[core, operators, subjects] # It is the same as.

  import reactiveCrown/unitUtils
  import sugar
  import times

  # procs just for example
  proc focus() = return
  proc jumpTo() = return
  var onButtonClicked: proc()
  # ======================

  const doubleClickBorder_sec = 0.01'f

  let
    sbjOnBtnClicked = newPublishSubject[Unit]()

    dspOnBtnClicked =
      sbjOnBtnClicked.toObservable
        .doThat((_: Unit) => echo "\"Button\" has clicked!")
        .subscribeBlock:
          focus()

    obsOnBtnDoubleClicked =
      sbjOnBtnClicked.toObservable
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
    sbjOnBtnClicked.next()

##[
  Modules
  =======

  [core](reactiveCrown/core.html)
  -------------------------------

  | It is the core of this library.
  | It is useless by itself basically but, it is necessary to use reactiveCrown.
  | It will be implicitly imported by written "import reactiveCrown" .

  [subjects](reactiveCrown/subjects.html)
  ---------------------------------------

  It will be implicitly imported by written "import reactiveCrown" .

  [operators](reactiveCrown/operators.html)
  -----------------------------------------

  It will be implicitly imported by written "import reactiveCrown" .

  [unitUtils](reactiveCrown/unitUtils.html)
  -----------------------------------------

  To use this module, you need to explicitly import it by writing "import reactiveCrown/unitUtils".

]##

import reactiveCrown/core
import reactiveCrown/subjects
import reactiveCrown/operators

export core, subjects, operators

# Imported to generate the document of unitUtils by "nim doc --project" command.
import reactiveCrown/unitUtils
