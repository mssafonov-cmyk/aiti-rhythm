#ifndef Version
#define Version "1.5.1"
#endif
[Setup]
AppId={{C3878BC6-5661-4EF2-9444-402206FE98F3}
AppName=АйТи:Ритм
AppVersion={#Version}
AppPublisher=АйТи:Ритм contributors
DefaultDirName={localappdata}\Programs\AITI Rhythm
DefaultGroupName=АйТи Ритм
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
DisableProgramGroupPage=yes
LicenseFile=LICENSE
OutputDir=dist\installer
OutputBaseFilename=AITI-Rhythm-{#Version}-Setup
SetupIconFile=indicators.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=no
UninstallDisplayIcon={app}\Rhythm.exe

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Создать ярлык на рабочем столе"; Flags: checkedonce
Name: "autostart"; Description: "Запускать АйТи:Ритм при входе в Windows"; Flags: unchecked

[Files]
Source: "dist\Rhythm\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\АйТи Ритм"; Filename: "{app}\Rhythm.exe"; AppUserModelID: "AITI.Rhythm"; AppUserModelToastActivatorCLSID: "4CBE1BC9-68F4-48D6-A308-3168C614D8C2"
Name: "{userdesktop}\АйТи Ритм"; Filename: "{app}\Rhythm.exe"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "AITIRhythm"; ValueData: """{app}\Rhythm.exe"""; Tasks: autostart; Flags: uninsdeletevalue

Root: HKCU; Subkey: "Software\Classes\aiti-rhythm"; ValueType: string; ValueData: "URL:AITI Rhythm notification"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\aiti-rhythm"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\aiti-rhythm\DefaultIcon"; ValueType: string; ValueData: "{app}\Rhythm.exe,0"
Root: HKCU; Subkey: "Software\Classes\aiti-rhythm\shell\open\command"; ValueType: string; ValueData: """{app}\Rhythm.exe"" --notification ""%1"""

[Run]
Filename: "{app}\Rhythm.exe"; Description: "Открыть АйТи:Ритм"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{app}\RhythmCore.exe"; Parameters: "--remove-antigravity-capture"; Flags: runhidden waituntilterminated; RunOnceId: "RestoreAntigravity"
Filename: "{app}\RhythmCore.exe"; Parameters: "--shutdown"; Flags: runhidden waituntilterminated; RunOnceId: "StopRhythm"

[Code]
function PrepareToInstall(var NeedsRestart: Boolean): String;
var ResultCode: Integer;
begin
  Result := '';
  if FileExists(ExpandConstant('{app}\RhythmCore.exe')) then
  begin
    if not Exec(ExpandConstant('{app}\RhythmCore.exe'), '--shutdown', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) or (ResultCode <> 0) then
      Result := 'Закройте АйТи:Ритм через меню в трее и повторите установку.';
  end;
end;
