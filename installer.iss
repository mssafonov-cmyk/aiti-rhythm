#ifndef Version
#define Version "1.3.0"
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
Name: "{group}\АйТи Ритм"; Filename: "{app}\Rhythm.exe"
Name: "{userdesktop}\АйТи Ритм"; Filename: "{app}\Rhythm.exe"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "AITIRhythm"; ValueData: """{app}\Rhythm.exe"""; Tasks: autostart; Flags: uninsdeletevalue

[Run]
Filename: "{app}\Rhythm.exe"; Description: "Открыть АйТи:Ритм"; Flags: nowait postinstall skipifsilent

[UninstallRun]
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
