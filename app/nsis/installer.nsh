# Restores support for installation directories containing spaces.
#
# NSIS itself defines /D as "everything after /D= up to the end of the command line", so
# it may contain spaces. electron-builder however re-reads the switch in multiUser.nsh with
# ${StdUtils.GetParameter} "D", which tokenizes on whitespace and therefore returns only
# the part before the first space: installing into "C:\DbGate Custom Dir" silently ends up
# in "C:\DbGate" (dbgate/dbgate#858).
#
# customInit runs after initMultiUser, so the truncated $INSTDIR can be corrected here by
# re-reading the raw command line.

!include LogicLib.nsh
!include FileFunc.nsh

!macro customInit
  ClearErrors
  ${GetParameters} $R8
  ${If} ${Errors}
    ClearErrors
  ${Else}
    # find "/D=" and take the rest of the command line verbatim, as NSIS documents it
    StrCpy $R9 0
    ${Do}
      StrCpy $R7 $R8 3 $R9
      ${If} $R7 == ""
        ${Break}
      ${EndIf}
      ${If} $R7 == "/D="
        IntOp $R9 $R9 + 3
        StrCpy $R6 $R8 "" $R9
        # a quoted value is not valid for /D, but tolerate it rather than creating a
        # directory whose name starts with a quote
        StrCpy $R7 $R6 1
        ${If} $R7 == '"'
          StrCpy $R6 $R6 "" 1
          StrCpy $R7 $R6 "" -1
          ${If} $R7 == '"'
            StrCpy $R6 $R6 -1
          ${EndIf}
        ${EndIf}
        ${If} $R6 != ""
          StrCpy $INSTDIR $R6
        ${EndIf}
        ${Break}
      ${EndIf}
      IntOp $R9 $R9 + 1
    ${Loop}
  ${EndIf}
!macroend
