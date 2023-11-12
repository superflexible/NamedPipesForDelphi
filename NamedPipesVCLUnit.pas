unit NamedPipesVCLUnit;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Pipes, Vcl.StdCtrls;

const cPipeName='NamedPipesVCLTesterPipe';

      cClientMessage:RawByteString='Test Msg from Client';
      cServerMessage:RawByteString='Test Msg from Server';

type
  TFNamedPipesTester = class(TForm)
    memServer: TMemo;
    memClient: TMemo;
    btStartServer: TButton;
    btStopServer: TButton;
    btConnect: TButton;
    btSendMsgToServer: TButton;
    btDisconnect: TButton;
    btSendMsgToClient: TButton;
    memGeneralLog: TMemo;
    procedure FormCreate(Sender: TObject);

    procedure NamedPipeServerPipeMessage(Sender: TObject; Pipe: HPIPE; Stream: TStream);
    procedure NamedPipeServerPipeConnect(Sender: TObject; Pipe: HPIPE);
    procedure NamedPipeServerPipeDisconnect(Sender: TObject; Pipe: HPIPE);
    procedure NamedPipeServerStopped(Sender: TObject);

    procedure NamedPipeClientPipeMessage(Sender: TObject; Pipe: HPIPE; Stream: TStream);
    procedure NamedPipeClientPipeDisconnect(Sender: TObject; Pipe: HPIPE);

    procedure btStartServerClick(Sender: TObject);
    procedure btStopServerClick(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure btConnectClick(Sender: TObject);
    procedure btSendMsgToServerClick(Sender: TObject);
    procedure btDisconnectClick(Sender: TObject);
    procedure btSendMsgToClientClick(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
    NamedPipeClient: TPipeClient;
    NamedPipeServer: TPipeServer;
  end;

var
  FNamedPipesTester: TFNamedPipesTester;

implementation

{$R *.dfm}

procedure GeneralDebugLog(a:string);
begin
  if Assigned(FNamedPipesTester) and Assigned(FNamedPipesTester.memGeneralLog) then
     FNamedPipesTester.memGeneralLog.Lines.Add(a);
  end;

function Stream2String(const AStream: TStream;const SetCPUTF8:Boolean=true): RawByteString;
var p:Int64;
begin
  p:=AStream.Position;
  AStream.Position:=0;
  SetLength(Result,AStream.Size);
  if AStream.Size>0 then
     AStream.Read(Result[1],AStream.Size);
  AStream.Position:=p;
  if SetCPUTF8 then
     System.SetCodePage(Result, CP_UTF8 ,False);
  end;


procedure TFNamedPipesTester.btConnectClick(Sender: TObject);
begin
  NamedPipeClient.Connect(1000);
  end;

procedure TFNamedPipesTester.btDisconnectClick(Sender: TObject);
begin
  NamedPipeClient.Disconnect(true);
  memClient.Lines.Add('Disconnected');
  end;

procedure TFNamedPipesTester.btSendMsgToClientClick(Sender: TObject);
begin
  NamedPipeServer.Broadcast(cServerMessage[1],Length(cServerMessage));
  end;

procedure TFNamedPipesTester.btSendMsgToServerClick(Sender: TObject);
begin
  NamedPipeClient.Write(cClientMessage[1],Length(cClientMessage));
  end;

procedure TFNamedPipesTester.btStartServerClick(Sender: TObject);
begin
  if not NamedPipeServer.Active then begin
     NamedPipeServer.Active:=true;
     if NamedPipeServer.Active then
        memServer.Lines.Add('Server started')
     else
        memServer.Lines.Add('Server could not be started')
     end;
  end;

procedure TFNamedPipesTester.btStopServerClick(Sender: TObject);
begin
  if NamedPipeServer.Active then begin
     NamedPipeServer.Active:=false;
     memServer.Lines.Add('Server stopped');
     end;
  end;

procedure TFNamedPipesTester.FormCreate(Sender: TObject);
begin
  PipesLogProc:=GeneralDebugLog;
  NamedPipeClient:=TPipeClient.Create;
  NamedPipeServer:=TPipeServer.Create;

  with NamedPipeServer do begin
    Active:= False;
    PipeName:=cPipeName;
    MustBeFirstInstance:= true;
    OnPipeConnect := NamedPipeServerPipeConnect;
    OnPipeDisconnect := NamedPipeServerPipeDisconnect;
    OnPipeMessage := NamedPipeServerPipeMessage;
    OnServerStopped := NamedPipeServerStopped;
    end;

  with NamedPipeClient do begin
    PipeName:=cPipeName;
    OnPipeDisconnect := NamedPipeClientPipeDisconnect;
    OnPipeMessage := NamedPipeClientPipeMessage;
    end;
  end;

procedure TFNamedPipesTester.FormDestroy(Sender: TObject);
begin
  FreeAndNil(memClient);
  FreeAndNil(memServer);
  end;

procedure TFNamedPipesTester.NamedPipeClientPipeDisconnect(Sender: TObject; Pipe: HPIPE);
begin
  memClient.Lines.Add('Server disconnected from pipe #'+IntToStr(Pipe));
  end;

procedure TFNamedPipesTester.NamedPipeClientPipeMessage(Sender: TObject; Pipe: HPIPE; Stream: TStream);
begin
  memClient.Lines.Add('Received: '+Utf8ToString(Stream2String(Stream)));
  end;

procedure TFNamedPipesTester.NamedPipeServerPipeConnect(Sender: TObject; Pipe: HPIPE);
begin
  memServer.Lines.Add('New client connected with pipe #'+IntToStr(Pipe));
  end;

procedure TFNamedPipesTester.NamedPipeServerPipeDisconnect(Sender: TObject; Pipe: HPIPE);
begin
  memServer.Lines.Add('Client disconnected from pipe #'+IntToStr(Pipe));
  end;

procedure TFNamedPipesTester.NamedPipeServerPipeMessage(Sender: TObject; Pipe: HPIPE; Stream: TStream);
begin
  memServer.Lines.Add('Received: '+Utf8ToString(Stream2String(Stream))+' from pipe #'+IntToStr(Pipe));
  end;

procedure TFNamedPipesTester.NamedPipeServerStopped(Sender: TObject);
begin
  memServer.Lines.Add('Server stopped (or could not start)');
  end;

end.
