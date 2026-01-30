[Setup]
AppName=Photobooth
AppVersion=1.0.0
DefaultDirName={pf}\Photobooth
DefaultGroupName=Photobooth
OutputDir=build\installer
OutputBaseFilename=PhotoboothInstaller-PyInstaller
Compression=lzma
SolidCompression=yes
SetupIconFile=..\src\web\frontend\favicon.ico

[Files]
Source: "..\build\pyinstaller\dist\photobooth.exe"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Photobooth"; Filename: "{app}\photobooth.exe"
Name: "{commondesktop}\Photobooth"; Filename: "{app}\photobooth.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop icon"; GroupDescription: "Additional icons:"
