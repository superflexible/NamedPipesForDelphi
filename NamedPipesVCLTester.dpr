program NamedPipesVCLTester;

uses
  Vcl.Forms,
  NamedPipesVCLUnit in 'NamedPipesVCLUnit.pas' {FNamedPipesTester};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TFNamedPipesTester, FNamedPipesTester);
  Application.Run;
end.
