[Setup]
AppName=Hikari Novel
AppVersion=0.4.0
AppPublisher=Hikari
DefaultDirName={autopf}\Hikari Novel
DefaultGroupName=Hikari Novel
OutputDir=..\build\installer
OutputBaseFilename=HikariNovel_Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs

[Icons]
Name: "{group}\Hikari Novel"; Filename: "{app}\hikari_novel_flutter.exe"
Name: "{autodesktop}\Hikari Novel"; Filename: "{app}\hikari_novel_flutter.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\hikari_novel_flutter.exe"; Description: "{cm:LaunchProgram}"; Flags: nowait postinstall
