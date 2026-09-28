[Setup]
AppId={{6L903538-42B1-4596-G479-BJ779F21A65D}
AppName=Hiddify
AppVersion=3.0.8
AppPublisher=Hiddify
AppPublisherURL=https://github.com/hiddify/hiddify-next
AppSupportURL=https://github.com/hiddify/hiddify-next
AppUpdatesURL=https://github.com/hiddify/hiddify-next
DefaultDirName={autopf64}\Hiddify
DisableProgramGroupPage=yes
OutputDir=..\..\out
OutputBaseFilename=Hiddify-Windows-Setup-x64
Compression=lzma2/max
SolidCompression=yes
SetupIconFile=resources\app_icon.ico
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
CloseApplications=force

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "launchAtStartup"; Description: "Auto Start Hiddify"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Hiddify"; Filename: "{app}\Hiddify.exe"
Name: "{autodesktop}\Hiddify"; Filename: "{app}\Hiddify.exe"; Tasks: desktopicon
Name: "{userstartup}\Hiddify"; Filename: "{app}\Hiddify.exe"; WorkingDir: "{app}"; Tasks: launchAtStartup

[Run]
Filename: "{app}\Hiddify.exe"; Description: "{cm:LaunchProgram,Hiddify}"; Flags: nowait postinstall skipifsilent

[Code]
function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
begin
  Exec('taskkill', '/F /IM Hiddify.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := True;
end;
