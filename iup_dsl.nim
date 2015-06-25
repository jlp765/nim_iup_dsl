import
  re, os, iup, strutils, tables

###################################### Engine
############ Stack layout
var
  gstack : seq[PIhandle] = @[]
  glastWidget : PIhandle
  timerId: int = 0
  afterOnceCallbacks = initTable[string, Icallback]()
  whenIdleOnceCallbacks: seq[Icallback] = @[]
  whenIdleCallbacks: seq[Icallback] = @[]
  idleCallbacksIndx: int = 0
  textInitialStr: seq[PIhandle] = @[]
  hasIdle: bool = false
  

proc toCB(fp: proc): Icallback {.inline.} = return cast[Icallback](fp)

proc nulProc(ih:PIhandle): cint {.cdecl.} = 
  echo "e"
  return IUP_DEFAULT
  
proc nulToggleProc(ih:PIhandle, state: cint): cint {.cdecl.} = 
  echo "toggle: ",state
  return IUP_DEFAULT
  
proc nulListProc(ih:PIhandle, txt: cstring, itm, state: cint): cint {.cdecl.} = 
  echo "list: text: ",txt, " item: ", itm, " state: ", state
  return IUP_DEFAULT
  
proc nulTextProc(ih:PIhandle, c: cint, newValue: cstring): cint {.cdecl.} = 
  echo "text: ",newValue," c: ",c
  return IUP_DEFAULT

proc nulCanvasProc(ih:PIhandle, posX, posY: cfloat): cint {.cdecl.} = 
  echo "canvas: pos: ", posX, ", ", posY
  return IUP_DEFAULT
  
###
proc last*[T](st: seq[T]) : T {.inline.} =
  result = st[st.high]

proc lastPos*() : int {.inline.} =
  result = gstack.high
  
proc getWin*() : PIhandle {.inline.} =
  result = gstack[0]
  
proc push[T](st: var seq[T], e: T) : T {.discardable.} =
  st.add(e)
  echo "push"
  result = e
# pop already defined ...

#############
proc option*(w: PIhandle, which, valu: string): PIhandle {.discardable.} =
  var 
    wS = which.toUpper()
    # not all values as upperCase
    vS = if wS in ["TITLE", "TEXT", "VALUESTRING"]: valu else: valu.toUpper()
  w.setAttribute(wS.cstring, vS.cstring)
  result = w

proc option*(which, valu: string): PIhandle {.discardable, inline.} =
  # use last pushed widget as widget to have option set
  result = glastWidget.option(which.toUpper(), valu.toUpper())

proc appendW(w: PIhandle) : void =
  glastWidget = w
  gstack.add(w)
  discard setHandle("item" & $lastPos(), w)
  w.option("padding", "0x0")
  w.option("expand","yes")
  echo "appendW: after stackSize: ", gstack.len

proc appendWi(w: PIhandle): void = 
  glastWidget = w
  gstack.add(w)
  discard setHandle("item" & $lastPos(), w)
  w.option("padding", "10x10")
  w.option("EXPAND","no")
  echo "appendWi: after stackSize: ", gstack.len

template apply(w: PIhandle, code: stmt) : stmt {.immediate.} =
  # margin inside, and items have no padding
  var contentPos = gstack.len   # items after the current last
  code          # widgets are added to the stack
  echo "Code stackSize: ", contentPos
  for i in contentPos .. gstack.len-1:
    iup.append(w, gstack[i])
  w.option("margin", "0x0")
  w.option("gap", "10x10")
  for i in contentPos .. gstack.len-1:
    discard gstack.pop()   
  glastWidget = gstack.last

template applyi(w: PIhandle, code: stmt) : stmt {.immediate.} =
  # no margin in here because items have their own padding
  var contentPos = gstack.len   # items after the current last
  code          # widgets are added to the stack
  echo "Code stackSize: ", contentPos
  for i in contentPos .. gstack.len-1:
    iup.append(w, gstack[i])
  w.option("margin", "10x10")
  w.option("gap", "0x0")
  for i in contentPos .. gstack.len-1:
    discard gstack.pop()   
  glastWidget = gstack.last
  
template anim*(w: PIhandle, ms: int, pproc: proc) : stmt {.immediate.} =
  #discard g_timeout_add(ms, pproc,0)
  discard setCallback(w, "ACTION", toCB(pproc))
  setAttribute(w, "TIME".cstring, ($ms).cstring)
  setAttribute(w, "RUN".cstring, "YES".cstring)
  
proc after*(ms: int, pproc: proc): PIhandle =
  let n = timerId
  inc timerId
  var t = iup.timer()
  discard iup.setHandle("iupTimer" & $n, t)
  t.setAttribute("TIME".cstring, ($ms).cstring)
  t.setAttribute("RUN".cstring, "YES".cstring)
  discard t.setCallback("ACTION_CB", toCB(pproc))
  result = t

proc onceProc(w: PIhandle): cint =
  w.setAttribute("RUN","NO")
  var p: Icallback = afterOnceCallbacks.mget($(w.getName()))
  #echo w.getName(), " calling the callback"
  #echo "Proc is: ",repr(afterOnceCallbacks.mget($(w.getName())))
  try:
    discard toCB(afterOnceCallbacks.mget($(w.getName())))(w)
  except:
    echo "Error running callback: ", w.getName()
    discard
  afterOnceCallbacks.del($(w.getName()))
  return IUP_DEFAULT

proc afterOnce*(ms: int, pproc: proc): PIhandle =
  let n = timerId
  inc timerId
  var t = iup.timer()
  discard iup.setHandle("iupTimer" & $n, t)
  t.setAttribute("TIME", $ms)
  t.setAttribute("RUN", "YES")
  discard t.setCallback("ACTION_CB", toCB(onceProc))
  afterOnceCallbacks.add($(t.getName()), toCB(pproc))
  result = t

proc stopTimer*(p: PIhandle) =
  p.setAttribute("RUN","NO")

proc startTimer*(p: PIhandle; ms: int = 0) =  
  if ms > 0:
    echo "setting time to :", ms
    p.setAttribute("TIME", $ms)
  # must set running AFTER time has been changed, not before!!
  p.setAttribute("RUN","Yes")

proc doIdleProcessing(w: PIhandle): cint {.cdecl.} =
  if not hasIdle: return IUP_DEFAULT
  var rem: seq[int] = @[]
  var res: int = 0
  if whenIdleOnceCallbacks.len > 0:
    discard whenIdleOnceCallbacks[0](w)
    whenIdleOnceCallbacks.delete(0)
  if whenIdleCallbacks.len > 0:
    if idleCallbacksIndx >= whenIdleCallbacks.len:
      idleCallbacksIndx = 0
    res = (whenIdleCallbacks[idleCallbacksIndx])(w)
    #echo "idel res: ", res, " default: ", IUP_DEFAULT
    if res != IUP_DEFAULT:
      whenIdleCallbacks.delete(idleCallbacksIndx)
    else:
      inc idleCallbacksIndx
    if iup.loopStep() == IUP_CLOSE:
      iup.exitLoop()
  return IUP_DEFAULT
      
proc whenIdle*(pproc: proc) =
  #echo "Setting Idle function"
  if pproc != nulProc:
    hasIdle = true
    whenIdleCallbacks.add(toCB(pproc))
    
proc whenIdleOnce*(pproc: proc) =
  if pproc != nulProc:
    hasIdle = true
    whenIdleOnceCallbacks.add(toCB(pproc))
  
proc mainQuit*(widget: PIhandle): cint {.cdecl.} =
  return IUP_CLOSE

proc mainQuitAsk*(widget: PIhandle): cint {.cdecl.} =
  if iup.alarm("Exit?", "Exit now?","Yes","No",nil) == 1:
    return IUP_CLOSE
  return IUP_IGNORE

############
template iup_app_content(code: stmt) : stmt {.immediate.} =
  discard iup.open(nil,nil)
  let content = iup.vbox(nil)
  let  win = iup.dialog(content)
  gstack.push(win)
  discard setHandle("item0", win)
  appendW(content)
  echo "Dialog\n","vbox"
  apply(content, code)

template iup_app_run(win: PIhandle) : stmt {.immediate.} =
  discard setCallback(win, "CLOSE_CB", toCB(mainQuit))
  if hasIdle:
    discard setFunction("IDLE_ACTION", toCB(doIdleProcessing))
  win.show()
  # set the inital values of text widgets
  for PIh in textInitialStr:
    var 
      s = PIh.getAttribute("USERVALUE")
      ss = PIh.getAttribute("SPINUSERVALUE")
    if not isNil(ss):
      echo "SS: ",ss
      PIh.setAttribute("SPINVALUE", ss)
    else:
      echo "S: ",s
      PIh.setAttribute("INSERT", s)
  textInitialStr = @[]
  # do it
  iup.mainloop()
  
template iup_appWH*(title: string,
                  width: int,
                  height: int,
                  code: stmt
                  ): stmt {.immediate.} =
  iup_app_content(code)
  let w = getWin()
  w.option("TITLE", "IUP: " & title)
  w.option("SIZE", $width & "x" & $height)
  iup_app_run(w)

template iup_app*(title: string,
                  code: stmt
                  ): stmt {.immediate.} =
  iup_app_content(code)
  let w = getWin()
  w.option("TITLE", "IUP: " & title)
  iup_app_run(w)
  
proc CPWIDGET*(obj: pointer): PIhandle {.inline.} =
  result = cast[PIhandle](obj)

proc CPBOX*(obj: pointer): PIhandle {.inline.} =
  result = cast[PIhandle](obj)

######################################## Layout

template stack*(code: stmt): stmt {.immediate.} =
  let content = iup.vbox(nil)
  appendW(content)
  echo "vbox"
  content.apply(code)
  
template stackFrame*(title: string, code: stmt): stmt {.immediate.} =
  let content = iup.vbox(nil)
  let fr = iup.frame(content)
  appendW(fr)
  appendW(content)
  echo "frame\nvbox"
  content.apply(code)
  discard gstack.pop()    # remove vbox and leave fr as last entry
  glastWidget = fr
  fr.setAttribute("TITLE", title)

template flow*(code: stmt): stmt {.immediate.} =
  let content = iup.hbox(nil)
  appendW(content)
  echo "hbox"
  content.apply(code)

template flowFrame*(title: string, code: stmt): stmt {.immediate.} =
  let content = iup.hbox(nil)
  let fr = iup.frame(content)
  fr.setAttribute("TITLE", title)
  appendW(fr)
  appendW(content)
  echo "frame\nhbox"
  content.apply(code)
  discard gstack.pop()    # remove hbox and leave fr as last entry
  glastWidget = fr

template stacki*(code: stmt): stmt {.immediate.} =
  let content = iup.vbox(nil)
  appendWi(content)
  echo "vbox"
  applyi(content, code)

template stackFramei*(title: string, code: stmt): stmt {.immediate.} =
  let content = iup.vbox(nil)
  let fr = iup.frame(content)
  appendWi(fr)
  appendWi(content)
  echo "frame\nvbox"
  content.applyi(code)
  discard gstack.pop()    # remove vbox and leave fr as last entry
  glastWidget = fr
  fr.setAttribute("TITLE", title)

template flowi*(code: stmt): stmt {.immediate.} =
  let content = iup.hbox(nil)
  appendWi(content)
  echo "hbox"
  applyi(content, code)

template flowFramei*(title: string, code: stmt): stmt {.immediate.} =
  let content = iup.hbox(nil)
  let fr = iup.frame(content)
  fr.option("title", title)
  appendWi(fr)
  appendWi(content)
  echo "frame\nhbox"
  content.applyi(code)
  discard gstack.pop()    # remove hbox and leave fr as last entry
  glastWidget = fr
  
discard """
################################################## Canvas
var gcurrentCanvas : PIhandle

template canvas(width, height: int, actn = nulCanvasProc, code: stmt) : stmt {.immediate.} =
  let c = iup.canvas(nil)
  if f != nulProc:
    discard setCallback(c, "ACTION", toCB(actn))
  if sloti:   appendWi(c) else:  appendW(c)
  echo "canvas"
  glastWidget = c
  

template handle_expose(pproc: proc) : stmt {.immediate.} =
  discard gcurrentCanvas.signal_connect( "expose-event", SIGNAL_FUNC(pproc), gcurrentCanvas.window)

template handle_button_press(pproc: proc) : stmt {.immediate.} =
  discard gcurrentCanvas.signal_connect( "button-press-event", SIGNAL_FUNC(pproc), gcurrentCanvas.window)

template handle_button_motion(pproc: proc) : stmt {.immediate.} =
  discard gcurrentCanvas.signal_connect( "motion-notify-event", SIGNAL_FUNC(pproc), gcurrentCanvas.window)

template handle_button_release(pproc: proc) : stmt {.immediate.} =
  discard gcurrentCanvas.signal_connect( "button-release-event", SIGNAL_FUNC(pproc), gcurrentCanvas.window)

template handle_Timer(ms: int,pproc: proc) : stmt {.immediate.} =
  discard g_timeout_add(ms, pproc, gcurrentCanvas.window)
"""

################################################## Widgets

#####  Button

proc bbutton(label, image: string, f = nulProc, sloti: bool): PIhandle {.discardable.} =
  let btn = iup.button(label, nil)
  if not isNil(image):
    if (image.existsFile()) or (image.find(re"^gtk-") > -1):
      btn.setAttribute("IMAGE", image)
  if f != nulProc:
    discard setCallback(btn, "ACTION", toCB(f))
  if sloti:   appendWi(btn) else:  appendW(btn)
  echo "button"
  return glastWidget

proc button*(label: string, f = nulProc): PIhandle {.discardable.} =
  return bbutton(label, nil, f, false)

proc button*(label, image: string, f = nulProc): PIhandle {.discardable.} =
  return bbutton(label, image, f, false)
  
proc buttoni*(label: string, f = nulProc): PIhandle {.discardable.}  =
  return bbutton(label, nil, f, true)
  
proc buttoni*(label, image: string; f = nulProc): PIhandle {.discardable.}  =
  return bbutton(label, image, f, true)

#####  Label
  
proc blabel(label: string, sloti: bool): PIhandle {.discardable.} =
  let lbl = iup.label(label)
  if sloti:   appendWi(lbl) else:  appendW(lbl)
  echo "label"
  return glastWidget

proc label*(label: string): PIhandle {.discardable.} =
  return blabel(label, false)

proc labeli*(label: string): PIhandle {.discardable.} =
  return blabel(label, true)

#####  List
  
proc blist(data: openArray[string], f = nulListProc, sloti = false, 
            multiSelect = false, ddn = false, editBox = false,
            sort = false): PIhandle {.discardable.} =
  let lst = iup.list(nil)
  if f != nulListProc:
    lst.setCallback("ACTION", toCB(f))
  if sloti:   appendWi(lst) else:  appendW(lst)
  lst.option("multiple", $multiSelect).option("dropdown", $ddn)
  if data.len > 0: 
    #lst.setAttribute("0", "Select one of the following:".cstring)
    for i,x in pairs(data):
      lst.setAttribute($(i+1), x.cstring)
    lst.setAttribute($(data.len+1), "".cstring)
  lst.option("editbox", $editBox).option("sort", $sort)
  echo "list"
  return glastWidget

proc list*[T](data: openArray[T]; actn = nulListProc; multiSelect = false;
            editBox = false; sort = false): PIhandle {.discardable.} =
  var arr: seq[string] = @[]
  for x in data:
    arr.add($x)
  return blist(arr, actn, false, multiSelect, false, editBox, sort)
  
proc listi*(data: openArray[string]; actn = nulListProc; multiSelect = false;
            editBox = false; sort = false): PIhandle {.discardable, inline.} =
  return blist(data, actn, true, multiSelect, false, editBox, sort)

proc listi*[T](data: openArray[T]; actn = nulListProc; multiSelect = false;
            editBox = false; sort = false): PIhandle {.discardable.} =
  var arr: seq[string] = @[]
  for x in data:
    arr.add($x)
  return blist(arr, actn, true, multiSelect, false, editBox, sort)

#####  DropDown List

proc ddnList*(data: openArray[string]; actn = nulListProc; multiSelect = false;
            editBox = false; sort = false): PIhandle {.discardable, inline.} =
  return blist(data, actn, false, multiSelect, true, editBox, sort)

proc ddnList*[T](data: openArray[T]; actn = nulListProc; multiSelect = false;
            editBox = false; sort = false): PIhandle {.discardable.} =
  var arr: seq[string] = @[]
  for x in data:
    arr.add($x)
  return blist(arr, actn, false, multiSelect, true, editBox, sort)
  
proc ddnListi*(data: openArray[string]; actn = nulListProc; multiSelect = false;
            editBox = false; sort = false): PIhandle {.discardable, inline.} =
  return blist(data, actn, true, multiSelect, true, editBox, sort)

proc ddnListi*[T](data: openArray[T]; actn = nulListProc; multiSelect = false;
            editBox = false; sort = false): PIhandle {.discardable.} =
  var arr: seq[string] = @[]
  for x in data:
    arr.add($x)
  return blist(arr, actn, true, multiSelect, true, editBox, sort)

##### Toggle  (checkbox)

proc btoggle(text: string; f = nulToggleProc; sloti = false;
             value = "off"; triState = false): PIhandle {.discardable.} =
  let tggl = iup.toggle(text, nil)  # text is called TITLE in iup
  if f != nulToggleProc:
    tggl.setCallback("ACTION", toCB(f))
  if sloti:   appendWi(tggl) else:  appendW(tggl)
  tggl.option("3state", $triState)
  tggl.option("value", $value)
  echo "toggle (3State: " & $triState & ")"
  return glastWidget

proc toggle*(text: string; actn = nulToggleProc; 
              value = "off"; triState = false): PIhandle {.discardable.} =
  result = btoggle(text, actn, false, value=value, triState=triState)
  
proc toggle*(texts: openArray[string]; actn = nulToggleProc; 
              value = "off"; triState = false): PIhandle {.discardable.} =
  for text in texts:
    result = btoggle(text, actn, false, value=value, triState=triState)

proc togglei*(text: string; actn = nulToggleProc; 
              value = "off"; triState = false): PIhandle {.discardable, inline.} =
  result = btoggle(text, actn, true, value=value, triState=triState)
    
proc togglei*(texts: openArray[string]; actn = nulToggleProc; 
              value = "off"; triState = false): PIhandle {.discardable, inline.} =
  for text in texts:
    result = btoggle(text, actn, true, value=value, triState=triState)

##### RadioStack  (needs toggles as children)

template radioStack*(code: stmt): stmt {.immediate.} =
  let content = iup.vbox(nil)
  let rdio = iup.radio(content)
  appendW(rdio)
  appendW(content)
  echo "radio\nvbox"
  apply(content, code)
  discard gstack.pop()    # remove vbox and leave fr as last entry
  glastWidget = rdio

template radioStacki*(code: stmt): stmt {.immediate.} =
  let content = iup.vbox(nil)
  let rdio = iup.radio(content)
  appendWi(rdio)
  appendWi(content)
  echo "radio\nvbox"
  applyi(content, code)
  discard gstack.pop()    # remove vbox and leave fr as last entry
  glastWidget = rdio

template radioStackFrame*(title: string, code: stmt): stmt {.immediate.} =
  let content = iup.vbox(nil)
  let rdio = iup.radio(content)
  let fr = iup.frame(rdio)
  fr.option("title", title)
  appendW(fr)
  appendW(rdio)
  appendW(content)
  echo "frame\nradio\nvbox"
  content.apply(code)
  discard gstack.pop()    # remove vbox and leave fr as last entry
  discard gstack.pop()    # remove radio and leave fr as last entry
  glastWidget = fr

template radioStackFramei*(title: string, code: stmt): stmt {.immediate.} =
  let content = iup.vbox(nil)
  let rdio = iup.radio(content)
  let fr = iup.frame(rdio)
  fr.option("title", title)
  appendWi(fr)
  appendWi(content)
  echo "frame\nvbox"
  content.applyi(code)
  discard gstack.pop()    # remove vbox and leave fr as last entry
  discard gstack.pop()    # remove radio and leave fr as last entry
  glastWidget = fr
  
##  radioFlow   (needs toggles as children)
template radioFlow*(code: stmt): stmt {.immediate.} =
  let content = iup.hbox(nil)
  let rdio = iup.radio(content)
  appendW(rdio)
  appendW(content)
  echo "radio\nhbox"
  apply(content, code)
  discard gstack.pop()    # remove hbox and leave fr as last entry
  glastWidget = rdio

template radioFlowi*(code: stmt): stmt {.immediate.} =
  let content = iup.hbox(nil)
  let rdio = iup.radio(content)
  appendWi(rdio)
  appendWi(content)
  echo "radio\nhbox"
  applyi(content, code)
  discard gstack.pop()    # remove hbox and leave fr as last entry
  glastWidget = rdio

template radioFlowFrame*(title: string, code: stmt): stmt {.immediate.} =
  let content = iup.hbox(nil)
  let rdio = iup.radio(content)
  let fr = iup.frame(rdio)
  fr.option("title", title)
  appendW(fr)
  appendW(rdio)
  appendW(content)
  echo "frame\nradio\nhbox"
  content.apply(code)
  discard gstack.pop()    # remove hbox and leave fr as last entry
  discard gstack.pop()    # remove radio and leave fr as last entry
  glastWidget = fr

template radioFlowFramei*(title: string, code: stmt): stmt {.immediate.} =
  let content = iup.hbox(nil)
  let rdio = iup.radio(content)
  let fr = iup.frame(rdio)
  fr.option("title", title)
  appendWi(fr)
  appendWi(rdio)
  appendWi(content)
  echo "frame\nhbox"
  content.applyi(code)
  discard gstack.pop()    # remove hbox and leave fr as last entry
  discard gstack.pop()    # remove radio and leave fr as last entry
  glastWidget = fr

#####  Text

proc btext(str: string, f = nulTextProc; sloti = false;
            multiLine = true; border = true; maxChars = 0;
            password = false; readOnly = false; scrollbar = "yes";
            autoHide = true; tabSize = 4; columns = 25; rows = 3;
            wordWrap = false): PIhandle {.discardable.} =
  let txt = iup.text(nil)
  if f != nulTextProc:
    txt.setCallback("ACTION", toCB(f))
  if sloti:   appendWi(txt) else:  appendW(txt)
  txt.option("multiline", if multiLine: "yes" else: "no")
  if multiLine:
    txt.option("tabsize", $tabSize)
    txt.option("scrollbar", scrollbar).option("autohide", if autoHide: "yes" else: "no")
  else:
    txt.option("password", if password: "yes" else: "no")
    #txt.option("size","x20")
  txt.option("readonly", if readOnly: "yes" else: "no")
  txt.option("border", if border: "yes" else: "no")
  txt.option("nc", $maxChars)
  txt.option("visiblecolumns", $columns).option("visiblelines", $rows)
  txt.setAttribute("USERVALUE", str)    # can only be inserted after iup maps the widget
  textInitialStr.add(txt)
  echo "text"
  return glastWidget

proc text*(text: string, actn = nulTextProc; multiLine = true;
           border = true; maxChars = 0; password = false; readonly = false;
           scrollbar = "yes"; autohide = true; columns = 25; rows = 5;
           tabSize = 4; wordWrap = false): PIhandle {.discardable, inline.} =
  return btext(text, actn, false, multiLine, border, maxChars,
                password, readOnly, scrollbar, autoHide, tabSize, 
                columns, rows, wordWrap)
                
proc texti*(text: string, actn = nulTextProc; multiLine = true;
           border = true; maxChars = 0; password = false; readonly = false;
           scrollbar = "yes"; autohide = true; columns = 25; rows = 5;
           tabSize = 4; wordWrap = false): PIhandle {.discardable, inline.} =
  return btext(text, actn, true, multiLine, border, maxChars,
                password, readOnly, scrollbar, autoHide, tabSize, 
                columns, rows, wordWrap)

proc textLine*(text: string, actn = nulTextProc; 
           border = true; maxChars = 0; password = false; readonly = false;
           columns = 25; tabSize = 4): PIhandle {.discardable, inline.} =
  return btext(text, actn, false, multiLine=false, border, maxChars,
                password, readOnly, scrollbar="NO", autoHide=true, tabSize, 
                columns, rows=0, wordWrap=false)
                
proc textLinei*(text: string, actn = nulTextProc; 
           border = true; maxChars = 0; password = false; readonly = false;
           columns = 25; tabSize = 4): PIhandle {.discardable, inline.} =
  return btext(text, actn, true, multiLine=false, border, maxChars,
                password, readOnly, scrollbar="NO", autoHide=true, tabSize, 
                columns, rows=0, wordWrap=false)

proc password*(text: string, actn = nulTextProc; 
           border = true; maxChars = 0; columns = 25; tabSize = 4): PIhandle {.discardable, inline.} =
  return btext(text, actn, false, multiLine=false, border, maxChars,
                password=true, readOnly=false, scrollbar="NO", autoHide=true, tabSize, 
                columns, rows=0, wordWrap=false)
                
proc passwordi*(text: string, actn = nulTextProc; 
           border = true; maxChars = 0; columns = 25; tabSize = 4): PIhandle {.discardable, inline.} =
  return btext(text, actn, true, multiLine=false, border, maxChars,
                password=true, readOnly=false, scrollbar="NO", autoHide=true, tabSize, 
                columns, rows=0, wordWrap=false)
                
proc textCopy2Clipboard(t: PIhandle) {.inline.} = t.option("clipboard","copy")

proc textCut2Clipboard(t: PIhandle) {.inline.} = t.option("clipboard","cut")

proc textPasteFromClipboard(t: PIhandle) {.inline.} = t.option("clipboard","paste")

proc textClearClipboard(t: PIhandle) {.inline.} = t.option("clipboard","clear")

###### spin  (which is a variant of text)

proc bspin(str: string, f = nulTextProc; sloti = false; border = true; 
          readOnly = false; maxChars = 0; columns = 2;
          spinMin = 0; spinMax = 100; spinInc = 1; 
          spinAlign = "right"; spinWrap = false; spinAuto = true): PIhandle {.discardable.} =
  let spn = iup.text(nil)
  if f != nulTextProc:
    spn.setCallback("ACTION", toCB(f))
  if sloti:   appendWi(spn) else:  appendW(spn)
  spn.option("spin","yes")
  spn.option("multiline", "no").option("readonly", if readOnly: "yes" else: "no")
  spn.option("border", if border: "yes" else: "no")
  spn.option("nc", $maxChars)
  spn.option("visiblecolumns", $columns).option("visiblelines", "1")
  spn.option("spinmax", $spinMax).option("spinmin", $spinMin).option("spininc", $spinInc)
  spn.option("spinalign", $spinAlign).option("spinwrap", $spinWrap)
  spn.option("spinauto", $spinAuto)
  spn.setAttribute("SPINUSERVALUE", str.cstring)    # can only be inserted after iup maps the widget
  textInitialStr.add(spn)
  echo "spin"
  return glastWidget

proc spin*(text: string, actn = nulTextProc; border = true; 
            maxChars = 0; readOnly = false; columns = 2;
            spinMax = 100; spinMin = 0; spinInc = 1; 
            spinAlign = "right"; spinWrap = false; spinAuto = true): PIhandle {.discardable, inline.} =
  return bspin(text, actn, false, border, readOnly, maxChars, columns, 
                spinMin, spinMax, spinInc, spinAlign, spinWrap, spinAuto)
  
proc spini*(text: string, actn = nulTextProc; border = true; 
            maxChars = 0; readOnly = false; columns = 2;
            spinMax = 100; spinMin = 0; spinInc = 1; 
            spinAlign = "right"; spinWrap = false; spinAuto = true): PIhandle {.discardable, inline.} =
  return bspin(text, actn, true, border, readOnly, maxChars, columns, 
                spinMin, spinMax, spinInc, spinAlign, spinWrap, spinAuto)
                
##### Notebook   (Tabs)

template notebook*(tabNames = openArray[string], tabType = "top", code: stmt): stmt {.immediate.} =
  let tb = iup.tabs(nil)
  appendW(tb)
  echo "Notebook"
  tb.option("tabtype", tabType)
  tb.option("padding","2x2")      # !! warning - needed => causes memory overwriting left as the default 0x0
  tb.apply(code)
  for i in 0 .. tb.getChildCount()-1:
    let x = tb.getChild(i)
    x.option("tabtitle", tabNames[i])

template notebooki*(tabNames = openArray[string], tabType = "top", code: stmt): stmt {.immediate.} =
  let tb = iup.tabs(nil)
  appendWi(tb)
  echo "Notebook"
  tb.option("tabtype", tabType)
  tb.option("padding","2x2")      # !! warning - needed => causes memory overwriting left as the default 0x0
  tb.applyi(code)
  for i in 0 .. tb.getChildCount()-1:
    let x = tb.getChild(i)
    x.option("tabtitle", tabNames[i])
    
#####  image
discard """
proc image(name: string)  =
  var w = if existsFile(name):
      iup.image((name)
    else:
      imageNewFromStock(name, ICON_SIZE_BUTTON)
  append( w )
"""
proc pass*(n: int = 1) =
   label( "                              " )
   
when isMainModule:
  var timer1, timer2, timer3: PIhandle
  var cnt: int = 0
  proc btnOkClick(w: PIhandle): cint {.cdecl.} =
    echo "Ok"
    return IUP_DEFAULT
  proc btnCancelClick(w: PIhandle): cint {.cdecl.} =
    return mainQuit(w)
  proc tproc(w: PIhandle): cint {.cdecl.} =
    echo "ping from ", iup.getName(w), "  Cnt: ",cnt
    #timer1.setAttribute("RUN", "NO")
    if $(iup.getName(w)) == "iupTimer1": 
      echo "Stopping timer"
      #stopTimer("iupTimer1")
      stopTimer(timer1)
    return IUP_DEFAULT
  proc tStartAgain(w: PIhandle): cint {.cdecl.} =
    startTimer(timer1,2000)
    return IUP_DEFAULT
  proc idleF(w: PIhandle): cint {.cdecl.} = 
    inc cnt
    return IUP_DEFAULT
  proc lstProc(w: PIhandle, txt: cstring, itm, state: cint): cint {.cdecl.} =
    echo "List: text: ",txt, " item: ", itm," is: ",state, " name: ",w.getName()
    return IUP_DEFAULT
  proc tgglProc(w: PIhandle, state: cint): cint {.cdecl.} =
    echo "Toggle: state: ", state
    return IUP_DEFAULT
  
  #iup_appWH("Test app", 300, 250):
  iup_app("Test app"):
    notebook(@["Lists","Labels","Edits","Toggles", "Spins"], "top"):
      flowFrame("Lists: "):
        list(@["1","2","3","4","5"], lstProc)
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
          textLinei("The rain in Japan", password=true)  # , border=false
          passwordi("The rain in HongKong", border=false)
          password("The rain in China", border=false)
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
    #timer1 = after(5000, tproc)
    #timer2 = afterOnce(2000, tproc)
    #timer3 = afterOnce(6000, tStartAgain)
    whenIdleOnce(idleF)
    
