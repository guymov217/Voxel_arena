; The Windows installer of the download for people without Steam (NSIS 3). tools/package.py builds it, with
;   makensis -DPRODUCT="WRECKSMITH Demo" -DSLUG=WRECKSMITH-Demo -DVERSION=0.1 -DEXE=WRECKSMITH_Demo.exe -DSRC=<folder> -DOUT=<setup.exe> wrecksmith.nsi
; It installs for the current user (no administrator rights), into %LOCALAPPDATA%\Programs\<product>, with a Start
; menu entry, an optional desktop shortcut, and an uninstaller listed under Installed apps. Nothing is signed.
Unicode true
!include "MUI2.nsh"

!ifndef PRODUCT
  !define PRODUCT "WRECKSMITH Demo"
!endif
!ifndef SLUG
  !define SLUG "WRECKSMITH-Demo"
!endif
!ifndef VERSION
  !define VERSION "0.1"
!endif
!ifndef EXE
  !define EXE "WRECKSMITH_Demo.exe"
!endif
!ifndef SRC
  !error "pass -DSRC=<the folder to install>"
!endif
!ifndef OUT
  !define OUT "${SLUG}-${VERSION}-windows-setup.exe"
!endif

Name "${PRODUCT} ${VERSION}"
OutFile "${OUT}"
RequestExecutionLevel user
InstallDir "$LOCALAPPDATA\Programs\${PRODUCT}"
InstallDirRegKey HKCU "Software\${SLUG}" "InstallDir"
SetCompressor zlib
BrandingText "${PRODUCT} ${VERSION}"

VIProductVersion "${VERSION}.0.0"
VIAddVersionKey "ProductName" "${PRODUCT}"
VIAddVersionKey "FileDescription" "${PRODUCT} installer"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "LegalCopyright" ""

!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\${EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "Play ${PRODUCT}"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Section "${PRODUCT}" SecGame
  SectionIn RO
  SetOutPath "$INSTDIR"
  File /r "${SRC}/*.*"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  CreateDirectory "$SMPROGRAMS\${PRODUCT}"
  CreateShortcut "$SMPROGRAMS\${PRODUCT}\${PRODUCT}.lnk" "$INSTDIR\${EXE}"
  CreateShortcut "$SMPROGRAMS\${PRODUCT}\Uninstall ${PRODUCT}.lnk" "$INSTDIR\Uninstall.exe"
  WriteRegStr HKCU "Software\${SLUG}" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${SLUG}" "DisplayName" "${PRODUCT}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${SLUG}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${SLUG}" "Publisher" "WRECKSMITH"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${SLUG}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${SLUG}" "DisplayIcon" "$INSTDIR\${EXE}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${SLUG}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${SLUG}" "NoModify" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${SLUG}" "NoRepair" 1
SectionEnd

Section "Desktop shortcut" SecDesktop
  CreateShortcut "$DESKTOP\${PRODUCT}.lnk" "$INSTDIR\${EXE}"
SectionEnd

LangString DESC_SecGame ${LANG_ENGLISH} "The game."
LangString DESC_SecDesktop ${LANG_ENGLISH} "A shortcut on the desktop."
!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${SecGame} $(DESC_SecGame)
  !insertmacro MUI_DESCRIPTION_TEXT ${SecDesktop} $(DESC_SecDesktop)
!insertmacro MUI_FUNCTION_DESCRIPTION_END

; The uninstaller takes away only what was installed (the folder may be one the player chose), not saves or settings.
Section "Uninstall"
  Delete "$INSTDIR\${EXE}"
  Delete "$INSTDIR\libvoxelcore*.dll"
  Delete "$INSTDIR\README.txt"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  Delete "$SMPROGRAMS\${PRODUCT}\${PRODUCT}.lnk"
  Delete "$SMPROGRAMS\${PRODUCT}\Uninstall ${PRODUCT}.lnk"
  RMDir "$SMPROGRAMS\${PRODUCT}"
  Delete "$DESKTOP\${PRODUCT}.lnk"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${SLUG}"
  DeleteRegKey HKCU "Software\${SLUG}"
SectionEnd
