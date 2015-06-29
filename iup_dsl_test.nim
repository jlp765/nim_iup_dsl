import iup

include iup_dsl

var 
  timer1, timer2, timer3: PIhandle
  cnt: int = 0

proc btnOkClick(w: PIhandle): cint {.cdecl, procvar.} =
  echo "Ok"
  return IUP_DEFAULT
  
proc btnCancelClick(w: PIhandle): cint {.cdecl, procvar.} =
  return mainQuit(w)

proc tproc(w: PIhandle): cint {.cdecl, procvar.} =
  echo "ping from ", iup.getName(w), "  Cnt: ",cnt
  if $(iup.getName(w)) == "iupTimer0": 
    echo "Stopping timer"
    stopTimer(timer1)
  return IUP_DEFAULT
  
proc tStartAgain(w: PIhandle): cint {.cdecl, procvar.} =
  startTimer(timer1,1000)
  return IUP_DEFAULT
  
proc idleF(ih: PIhandle): cint {.cdecl, procvar.} = 
  inc cnt
  return IUP_DEFAULT
  
proc lstProc(w: PIhandle, txt: cstring, itm, state: cint): cint {.cdecl, procvar.} =
  echo "List: text: ",txt, " item: ", itm," is: ",state, " name: ",w.getName()
  return IUP_DEFAULT
  
proc tgglProc(w: PIhandle, state: cint): cint {.cdecl, procvar.} =
  echo "Toggle: state: ", state
  return IUP_DEFAULT

proc main() =  
  #iup_appWH("Test app", 300, 250):
  iup_app("Test app"):
    notebook(@["Lists","Labels","Edits","Toggles", "Spins"], "top"):
      flowFrame("Lists: "):
        list(@["item1","item2","item3","item4","item5"], lstProc)
        ddnList(@[1,2,3,4,5], lstProc, editBox=false)
      flowFrame("A titled flow frame, holding labels and buttons"):
        label("Wow, some text")
        label("Top level text ")
        stacki:
          buttoni("&Ok", btnOkClick)
          #option("SIZE", "20x20")
          #option("expand","horizontal")
          buttoni("E&xit", btnCancelClick)
          #option("SIZE", "40x20")
      flowFrame("Edits: "):
        text("The rain in Spain\nfalls from the sky", nulTextProc, 
                multiLine=true, scrollbar="vertical")
        stack:
          textLinei("Some p/word txt", password=true)  # , border=false
          passwordi("Some p/word txt#2", border=false)
          password("Some p/word txt#3", border=false)
      flowFrame("Toggles: "):
        radioStack:
          toggle(@["Option 1","Option 2","Option 3"], tgglProc)
        radioFlowFramei("Radio Flow"):
          toggle(@["Option 1","Option 2","Option 3"], tgglProc)
        stacki:
          toggle(@["Option 1","Option 2","Option 3"], tgglProc)
      flowframei("Spins: "):
        spini("26", columns=2)
        spin("1", spinMin=0, spinMax=5, spinWrap=true)
    timer1 = after(2000, tproc)   # show results of whenIdleOnce(), then stop, restarted then stop again
    timer3 = afterOnce(5000, tStartAgain)
    whenIdleOnce(idleF)
    
main()
