# Restores support for installation directories containing spaces.
#
# NSIS defines /D as "everything after /D= up to the end of the command line", so the path
# may contain spaces and NSIS itself parses it correctly. electron-builder however
# overwrites $INSTDIR in multiUser.nsh by re-reading the switch with
# ${StdUtils.GetParameter} "D", which tokenizes on whitespace and therefore keeps only the
# part before the first space: installing into "C:\DbGate Custom Dir" silently ended up in
# "C:\DbGate" (dbgate/dbgate#858).
#
# customInit runs right after initMultiUser, so the truncation is undone here. NSIS strips
# /D= from ${GetParameters}, hence the raw process command line is read.

!include LogicLib.nsh

!macro customInit
  System::Call 'kernel32::GetCommandLineW()t.R8'
  ${If} $R8 == ""
    System::Call 'kernel32::GetCommandLine()t.R8'
  ${EndIf}

  StrCpy $R9 0
  ${Do}
    StrCpy $R7 $R8 3 $R9
    ${If} $R7 == ""
      ${Break}
    ${EndIf}
    ${If} $R7 == "/D="
      IntOp $R9 $R9 + 3
      StrCpy $R6 $R8 "" $R9
      ${If} $R6 != ""
        StrCpy $INSTDIR $R6
      ${EndIf}
      ${Break}
    ${EndIf}
    IntOp $R9 $R9 + 1
  ${Loop}
!macroend
