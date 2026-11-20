; 悦音独立安装器；原Mconnect安装器与AppId保留。
#define MyAppName "DJ Music"
#define MyAppVersion "0.5.1"
#define MyAppExeName "yueyin_music.exe"
#define MyAppSourceDir "..\build\windows\x64\runner\Release"
[Setup]
AppId={{54A778C9-2261-4E1F-BA89-EE68844DA7AA}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=DJ Music Contributors
AppPublisherURL=https://github.com/sun-dove/yueyin-music
DefaultDirName={localappdata}\Programs\YueyinMusic
DefaultGroupName={#MyAppName}
UsePreviousGroup=no
DisableDirPage=no
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\build\yueyin-release
OutputBaseFilename=DJ-Music-Setup-{#MyAppVersion}-x64
SetupIconFile=..\windows\runner\resources\yueyin_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
LicenseFile=..\LICENSE
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
#if FileExists(AddBackslash(CompilerPath) + "Languages\ChineseSimplified.isl")
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
#endif
[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
[Files]
Source: "{#MyAppSourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
[Code]
function InitializeSetup(): Boolean;
begin
  Result := FileExists(ExpandConstant('{sys}\msvcp140.dll')) and FileExists(ExpandConstant('{sys}\vcruntime140.dll'));
  if not Result then
    MsgBox('请先安装微软 Visual C++ 2015-2022 x64 运行库，然后重新运行安装器。下载说明：https://learn.microsoft.com/cpp/windows/latest-supported-vc-redist', mbInformation, MB_OK);
end;

procedure RemovePreviousBrandShortcut(const ShortcutPath: String);
var
  Shell, Shortcut: Variant;
begin
  if not FileExists(ShortcutPath) then Exit;
  try
    Shell := CreateOleObject('WScript.Shell');
    Shortcut := Shell.CreateShortcut(ShortcutPath);
    if CompareText(Shortcut.TargetPath, ExpandConstant('{app}\{#MyAppExeName}')) = 0 then
      DeleteFile(ShortcutPath);
  except
    Log('旧快捷方式目标无法核对，保留该文件。');
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then begin
    RemovePreviousBrandShortcut(ExpandConstant('{autodesktop}\乐音音乐.lnk'));
    RemovePreviousBrandShortcut(ExpandConstant('{autodesktop}\悦音音乐.lnk'));
    RemovePreviousBrandShortcut(ExpandConstant('{autodesktop}\Meizuo Music.lnk'));
    RemovePreviousBrandShortcut(ExpandConstant('{autodesktop}\MZ Music.lnk'));
    RemovePreviousBrandShortcut(ExpandConstant('{userprograms}\乐音音乐\乐音音乐.lnk'));
    RemovePreviousBrandShortcut(ExpandConstant('{userprograms}\悦音音乐\悦音音乐.lnk'));
    RemovePreviousBrandShortcut(ExpandConstant('{userprograms}\Meizuo Music\Meizuo Music.lnk'));
    RemovePreviousBrandShortcut(ExpandConstant('{userprograms}\MZ Music\MZ Music.lnk'));
    RemoveDir(ExpandConstant('{userprograms}\乐音音乐'));
    RemoveDir(ExpandConstant('{userprograms}\悦音音乐'));
    RemoveDir(ExpandConstant('{userprograms}\Meizuo Music'));
    RemoveDir(ExpandConstant('{userprograms}\MZ Music'));
  end;
end;
