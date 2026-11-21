; The standard Windows NSIS distribution ships x86 Unicode stubs.
; The packaged application still requires a 64-bit version of Windows.
Target x86-unicode
RequestExecutionLevel user

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "x64.nsh"
!ifdef TEST_CERTIFICATE
!include "FileFunc.nsh"
!endif
!ifdef IDENTITY_PACKAGE
!include "WinVer.nsh"
!endif

Name "Sekai Soundbar"
OutFile "${SETUP}"
InstallDir "$LOCALAPPDATA\Programs\SekaiSoundbar"
VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "Sekai Soundbar"
VIAddVersionKey "FileDescription" "Sekai Soundbar setup"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "LegalCopyright" "Sekai Soundbar contributors. GPL-3.0."
SetCompressor /SOLID lzma

!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\SekaiSoundbar"
!define STARTUP_KEY "Software\Microsoft\Windows\CurrentVersion\Run"
!define MUI_ABORTWARNING
!insertmacro MUI_PAGE_LICENSE "${PAYLOAD_LICENSE}"
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN "$INSTDIR\app\SekaiSoundbar.exe"
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "Russian"

LangString Running ${LANG_ENGLISH} "Close Sekai Soundbar from its menu, then run setup again."
LangString Running ${LANG_RUSSIAN} "Закройте Sekai Soundbar через меню дока и запустите установщик снова."
LangString InstallFailed ${LANG_ENGLISH} "The program files could not be installed."
LangString InstallFailed ${LANG_RUSSIAN} "Не удалось установить файлы программы."
LangString RequiresX64 ${LANG_ENGLISH} "Sekai Soundbar requires a 64-bit version of Windows."
LangString RequiresX64 ${LANG_RUSSIAN} "Для Sekai Soundbar требуется 64-битная версия Windows."

Var InstanceGuard

!ifdef TEST_CERTIFICATE
LangString TestTrustPrompt ${LANG_ENGLISH} "This test build needs to add the Sekai Soundbar Test certificate to Local Computer → Trusted People. Allow this operation? Windows will request administrator approval."
LangString TestTrustPrompt ${LANG_RUSSIAN} "Для тестовой сборки нужно добавить сертификат Sekai Soundbar Test в хранилище «Локальный компьютер → Доверенные лица». Разрешить? Windows запросит подтверждение администратора."
LangString TestTrustFailed ${LANG_ENGLISH} "Windows does not trust the Sekai Soundbar Test certificate. Setup was stopped."
LangString TestTrustFailed ${LANG_RUSSIAN} "Windows не доверяет сертификату Sekai Soundbar Test. Установка остановлена."

Function CheckTestCertificate
    nsExec::Exec /TIMEOUT=15000 '$\"$WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe$\" -NoLogo -NoProfile -NonInteractive -Command $\"if (Test-Path -LiteralPath Cert:\LocalMachine\TrustedPeople\${TEST_CERT_THUMBPRINT}) { exit 0 }; exit 1$\"'
    Pop $0
FunctionEnd

Function TrustTestCertificate
    ; Only this mode runs elevated. Its PowerShell command comes from this executable.
    ; Read the DER once, check its SHA-256 and import those same bytes.
    InitPluginsDir
    SetOutPath "$PLUGINSDIR"
    File /oname=SekaiSoundbar-Test-Publisher.cer "${TEST_CERTIFICATE}"
    System::Call 'kernel32::SetEnvironmentVariableW(w "SEKAI_TEST_CERTIFICATE", w "$PLUGINSDIR\SekaiSoundbar-Test-Publisher.cer")'
    nsExec::Exec /TIMEOUT=30000 `$\"$WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe$\" -NoLogo -NoProfile -NonInteractive -Command $\"$$ErrorActionPreference='Stop'; $$b=[IO.File]::ReadAllBytes($$env:SEKAI_TEST_CERTIFICATE); $$h=[BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($$b)).Replace('-',''); if ($$h -ne '${TEST_CERT_SHA256}') { exit 1 }; $$c=[Security.Cryptography.X509Certificates.X509Certificate2]::new($$b); $$s=[Security.Cryptography.X509Certificates.X509Store]::new('TrustedPeople','LocalMachine'); $$s.Open('ReadWrite'); try { $$s.Add($$c) } finally { $$s.Close() }$\"`
    Pop $0
    SetErrorLevel $0
FunctionEnd
!endif

!ifdef IDENTITY_PACKAGE
LangString RequiresWin11 ${LANG_ENGLISH} "This edition of Sekai Soundbar requires Windows 11."
LangString RequiresWin11 ${LANG_RUSSIAN} "Для этой сборки Sekai Soundbar требуется Windows 11."
LangString IdentityInstallFailed ${LANG_ENGLISH} "Windows could not register Sekai Soundbar for access to app notifications."
LangString IdentityInstallFailed ${LANG_RUSSIAN} "Windows не удалось зарегистрировать Sekai Soundbar для доступа к уведомлениям приложений."
LangString IdentityRemoveFailed ${LANG_ENGLISH} "Windows could not remove Sekai Soundbar's notification registration."
LangString IdentityRemoveFailed ${LANG_RUSSIAN} "Windows не удалось удалить регистрацию Sekai Soundbar для уведомлений."

Var IdentityResult
Var IdentityMessage

!macro NOTIFICATION_IDENTITY ACTION
    InitPluginsDir
    SetOutPath "$PLUGINSDIR"
    File /oname=RegisterIdentity.ps1 "${IDENTITY_SCRIPT}"
    !if "${ACTION}" == "Install"
        File /oname=notification-identity.msix "${IDENTITY_PACKAGE}"
    !endif
    System::Call 'kernel32::SetEnvironmentVariableW(w "SEKAI_IDENTITY_SCRIPT", w "$PLUGINSDIR\RegisterIdentity.ps1")'
    System::Call 'kernel32::SetEnvironmentVariableW(w "SEKAI_IDENTITY_PACKAGE", w "$PLUGINSDIR\notification-identity.msix")'
    System::Call 'kernel32::SetEnvironmentVariableW(w "SEKAI_PROGRAM_DIR", w "$INSTDIR\app")'
    System::Call 'kernel32::SetEnvironmentVariableW(w "SEKAI_IDENTITY_ACTION", w "${ACTION}")'
    System::Call 'kernel32::SetEnvironmentVariableW(w "SEKAI_IDENTITY_NAME", w "${IDENTITY_NAME}")'
    System::Call 'kernel32::SetEnvironmentVariableW(w "SEKAI_IDENTITY_PUBLISHER", w "${IDENTITY_PUBLISHER}")'
    System::Call 'kernel32::SetEnvironmentVariableW(w "SEKAI_IDENTITY_VERSION", w "${VERSION}.0")'
    System::Call 'kernel32::SetEnvironmentVariableW(w "SEKAI_IDENTITY_ERROR", w "$PLUGINSDIR\identity-error.txt")'
    nsExec::Exec /TIMEOUT=120000 '$\"$WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe$\" -NoLogo -NoProfile -NonInteractive -Command $\"& ([ScriptBlock]::Create([IO.File]::ReadAllText($$env:SEKAI_IDENTITY_SCRIPT)))$\"'
    Pop $IdentityResult
    StrCpy $IdentityMessage ""
    ${If} $IdentityResult != 0
        ClearErrors
        FileOpen $0 "$PLUGINSDIR\identity-error.txt" r
        ${IfNot} ${Errors}
            FileSeek $0 2 SET ; Skip the UTF-16LE byte order mark written by PowerShell.
            FileReadUTF16LE $0 $IdentityMessage
            FileClose $0
        ${EndIf}
    ${EndIf}
!macroend
!endif

!macro ACQUIRE_LOCK
    ${IfNot} ${RunningX64}
        SetErrorLevel 1
        IfSilent +2
        MessageBox MB_ICONSTOP "$(RequiresX64)"
        Abort
    ${EndIf}
    SetShellVarContext current
    SetRegView 64
    System::Call 'kernel32::SetLastError(i 0)'
    System::Call 'kernel32::CreateMutexW(p 0, i 0, w "Local\SekaiSoundbar.Instance") p .r0 ?e'
    Pop $1
    StrCpy $InstanceGuard $0
    ${If} $0 == 0
    ${OrIf} $1 == 183
        SetErrorLevel 2
        IfSilent +2
        MessageBox MB_ICONEXCLAMATION "$(Running)"
        Abort
    ${EndIf}
!macroend

Function .onInit
    !ifdef TEST_CERTIFICATE
    ${GetParameters} $0
    ${If} $0 == "/SekaiTrustTestPublisher"
        SetSilent silent
        Call TrustTestCertificate
        Quit
    ${EndIf}
    !endif
    !insertmacro ACQUIRE_LOCK
    !ifdef IDENTITY_PACKAGE
    ${IfNot} ${AtLeastWin11}
        SetErrorLevel 1
        IfSilent +2
        MessageBox MB_ICONSTOP "$(RequiresWin11)"
        Abort
    ${EndIf}
    !endif
FunctionEnd

Function un.onInit
    !insertmacro ACQUIRE_LOCK
FunctionEnd

Section "Sekai Soundbar"
    !ifdef TEST_CERTIFICATE
    Call CheckTestCertificate
    ${If} $0 != 0
        IfSilent testTrustFailed
        MessageBox MB_YESNO|MB_ICONQUESTION|MB_DEFBUTTON2 "$(TestTrustPrompt)" IDNO testTrustFailed
        ExecShellWait "runas" "$EXEPATH" "/SekaiTrustTestPublisher" SW_HIDE
        Call CheckTestCertificate
        ${If} $0 != 0
            Goto testTrustFailed
        ${EndIf}
    ${EndIf}
    !endif
    SetOutPath "$INSTDIR"
    ; Recover the previous runtime if a prior upgrade was interrupted.
    IfFileExists "$INSTDIR\previous\SekaiSoundbar.exe" 0 stage
    IfFileExists "$INSTDIR\app\SekaiSoundbar.exe" discardBackup
    ClearErrors
    Rename "$INSTDIR\previous" "$INSTDIR\app"
    IfErrors failed
    Goto stage

discardBackup:
    RMDir /r "$INSTDIR\previous"

stage:
    RMDir /r "$INSTDIR\staging"
    SetOutPath "$INSTDIR\staging"
    ClearErrors
    File /r "${PAYLOAD_FILES}"
    IfErrors failed

    SetOutPath "$INSTDIR"
    WriteUninstaller "$INSTDIR\Uninstall.exe"
    IfErrors failed
    IfFileExists "$INSTDIR\app\SekaiSoundbar.exe" 0 replace
    Rename "$INSTDIR\app" "$INSTDIR\previous"
    IfErrors failed

replace:
    Rename "$INSTDIR\staging" "$INSTDIR\app"
    IfErrors rollback
    !ifdef IDENTITY_PACKAGE
    !insertmacro NOTIFICATION_IDENTITY Install
    SetOutPath "$INSTDIR"
    ${If} $IdentityResult != 0
        Goto identityFailed
    ${EndIf}
    !endif
    RMDir /r "$INSTDIR\previous"

    SetOutPath "$INSTDIR\app"
    CreateDirectory "$SMPROGRAMS\Sekai Soundbar"
    CreateShortCut "$SMPROGRAMS\Sekai Soundbar\Sekai Soundbar.lnk" "$INSTDIR\app\SekaiSoundbar.exe"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayName" "Sekai Soundbar"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayVersion" "${VERSION}"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\app\SekaiSoundbar.exe"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
    WriteRegStr HKCU "${UNINSTALL_KEY}" "QuietUninstallString" '$\"$INSTDIR\Uninstall.exe$\" /S'
    WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoModify" 1
    WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoRepair" 1
    System::Call 'kernel32::CloseHandle(p $InstanceGuard)'
    Goto done

!ifdef TEST_CERTIFICATE
testTrustFailed:
    SetErrorLevel 4
    IfSilent +2
    MessageBox MB_ICONSTOP "$(TestTrustFailed)"
    Abort
!endif

!ifdef IDENTITY_PACKAGE
identityFailed:
    RMDir /r "$INSTDIR\app"
    ${If} ${FileExists} "$INSTDIR\previous\SekaiSoundbar.exe"
        Rename "$INSTDIR\previous" "$INSTDIR\app"
    ${Else}
        Delete "$INSTDIR\Uninstall.exe"
        SetOutPath "$TEMP"
        RMDir "$INSTDIR"
    ${EndIf}
    DetailPrint "$IdentityResult $IdentityMessage"
    SetErrorLevel 3
    IfSilent +2
    MessageBox MB_ICONSTOP "$(IdentityInstallFailed)$\r$\n$IdentityResult $IdentityMessage"
    Abort
!endif

rollback:
    IfFileExists "$INSTDIR\previous\SekaiSoundbar.exe" 0 failed
    Rename "$INSTDIR\previous" "$INSTDIR\app"

failed:
    SetOutPath "$INSTDIR"
    RMDir /r "$INSTDIR\staging"
    SetErrorLevel 1
    IfSilent +2
    MessageBox MB_ICONSTOP "$(InstallFailed)"
    Abort

done:
SectionEnd

Section "Uninstall"
    !ifdef IDENTITY_PACKAGE
    ${If} ${AtLeastWin11}
        !insertmacro NOTIFICATION_IDENTITY Remove
        ${If} $IdentityResult != 0
            DetailPrint "$IdentityResult $IdentityMessage"
            SetErrorLevel 3
            IfSilent +2
            MessageBox MB_ICONSTOP "$(IdentityRemoveFailed)$\r$\n$IdentityResult $IdentityMessage"
            Abort
        ${EndIf}
    ${EndIf}
    !endif
    SetOutPath "$TEMP"
    ClearErrors
    IfFileExists "$INSTDIR\app\*.*" 0 +2
    RMDir /r "$INSTDIR\app"
    IfFileExists "$INSTDIR\previous\*.*" 0 +2
    RMDir /r "$INSTDIR\previous"
    IfFileExists "$INSTDIR\staging\*.*" 0 +2
    RMDir /r "$INSTDIR\staging"
    IfErrors uninstallFailed
    Delete "$SMPROGRAMS\Sekai Soundbar\Sekai Soundbar.lnk"
    RMDir "$SMPROGRAMS\Sekai Soundbar"
    ReadRegStr $0 HKCU "${STARTUP_KEY}" "SekaiSoundbar"
    ${If} $0 == '$\"$INSTDIR\app\SekaiSoundbar.exe$\"'
        DeleteRegValue HKCU "${STARTUP_KEY}" "SekaiSoundbar"
    ${EndIf}
    DeleteRegKey HKCU "${UNINSTALL_KEY}"
    Delete "$INSTDIR\Uninstall.exe"
    RMDir "$INSTDIR"
    Goto uninstallDone

uninstallFailed:
    SetErrorLevel 1
    Abort

uninstallDone:
SectionEnd
