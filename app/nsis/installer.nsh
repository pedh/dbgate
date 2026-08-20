# Restores support for installation directories containing spaces.
#
# NSIS defines /D as "everything after /D= up to the end of the command line", so the path
# may contain spaces, and NSIS itself parses it correctly. electron-builder however
# overwrites $INSTDIR in multiUser.nsh by re-reading the switch with
# ${StdUtils.GetParameter} "D", which tokenizes on whitespace and so returns only the part
# before the first space: installing into "C:\DbGate Custom Dir" silently ends up in
# "C:\DbGate" (dbgate/dbgate#858).
#
# customInit runs right after initMultiUser, so the damage can be undone here. NSIS strips
# /D= from ${GetParameters}, hence the raw process command line is used.

!include LogicLib.nsh

!macro customInit
  System::Call 'kernel32::GetCommandLine() t .r8'

  FileOpen $R5 "$TEMP\dbgate-nsis-init.log" w
  FileWrite $R5 "cmdline=[$R8]$\r$\n"
  FileWrite $R5 "instdir before=[$INSTDIR]$\r$\n"

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

  FileWrite $R5 "instdir after=[$INSTDIR]$\r$\n"
  FileClose $R5
!macroend
