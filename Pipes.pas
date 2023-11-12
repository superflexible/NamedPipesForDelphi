unit Pipes;

// This is a wonderful set of components for inter-process communication
// using Named Pipes. One of the best solutions when you need to communicate
// with an NT/2000/XP service, and/or communicate across an MS Windows network.
//
// Free Source Code, no license, no guarantee, no liability.
//
// The original author, Russell, gave this to me with no usage restrictions
// whatsoever.
//
// This package prepared by Tobias Giesen, tobias@tgtools.de
//
// Improved version for 32 and 64 bits released November 2023
// and tested with Delphi 12 (Athens)

// I also have a similar component for macOS and Linux/FreeBSD which
// uses sockets, please contact me if interested

interface

{$ifdef MSWINDOWS}

{$define EXTENDEDLOGGING}

uses
  Forms, Windows, SysUtils, Classes, Messages, SyncObjs;


type
{$ifdef USETGTHREADS}
   TThreadType=TTGThread;
{$else}
   TThreadType=TThread;
{$endif}

resourcestring

  // Exception resource strings
  resPipeActive     =  'Cannot change property while server is active!';
  resPipeConnected  =  'Cannot change property when client is connected!';
  resBadPipeName    =  'Invalid pipe name specified!';

const

  // Maximum and minimum constants
  MAX_THREADS       =  1001;     // 1 Listener and 1000 Workers
  MIN_BUFFER        =  4096;
  MAX_BUFFER        =  100*1024*1024;

const

  // Pipe window messages
  WM_PIPEERROR_L    =  WM_USER+100;
  WM_PIPEERROR_W    =  Succ(WM_PIPEERROR_L);
  WM_PIPECONNECT    =  Succ(WM_PIPEERROR_W);
  WM_PIPEDISCONNECT =  Succ(WM_PIPECONNECT);
  WM_PIPESEND       =  Succ(WM_PIPEDISCONNECT);
  WM_PIPEMESSAGE    =  Succ(WM_PIPESEND);

const PipesLogProc:procedure(a:string)=nil;

type

  // Define the pipe data type
  HPIPE             =  THandle;

  // Pipe exceptions
  EPipeException    =  class(Exception);

  // Forward declarations
  TPipeServer       =  class;
  TPipeClient       =  class;

  // Pipe write data structure
  PPipeWrite        =  ^TPipeWrite;
  TPipeWrite        =  packed record
     Buffer:        PChar;
     Count:         Integer;
  end;

  // Writer queue node structure
  PWriteNode        =  ^TWriteNode;
  TWriteNode        =  packed record
     PipeWrite:     PPipeWrite;
     NextNode:      PWriteNode;
  end;

  // Writer queue class
  TWriteQueue       =  class(TObject)
  private
     // Private declarations
     FDataEv:       THandle;
     FHead:         PWriteNode;
     FTail:         PWriteNode;

     FCritical:     TRTLCriticalSection;
  protected
     // Protected declarations
     procedure      Clear;
     function       NewNode(PipeWrite: PPipeWrite): PWriteNode;
  public
     // Public declarations
     constructor    Create;
     destructor     Destroy; override;
     procedure      Enqueue(PipeWrite: PPipeWrite);
     function       Dequeue: PPipeWrite;
     property       DataEvent: THandle read FDataEv;
     function       GetCount:Integer;
  end;

  // Base class pipe thread that has a SafeSynchronize method
  TPipeThread       =  class(TThreadType)
  private
     // Private declarations
  protected
     // Protected declarations
     procedure      SafeSynchronize(Method: TThreadMethod);
  public
     // Public declarations
  end;

  // Pipe Listen thread class
  TPipeListenThread =  class(TPipeThread)
  public
     // Private declarations
     FNotify:       HWND;
     FErrorCode:    Integer;
     FPipe:         HPIPE;
     FPipeName:     string;
     FConnected:    Boolean;
     FEvents:       Array [0..1] of THandle;
     FOlapConnect:  TOverlapped;
     FPipeServer:   TPipeServer;
     FSA:           TSecurityAttributes;
  protected
     // Protected declarations
     function       CreateServerPipe(const reopening:Boolean): Boolean;
     procedure      DoWorker;
     procedure      Execute; override;
  public
     // Public declarations
     FullPipeName: string;
     constructor    Create(PipeServer: TPipeServer; KillEvent: THandle);
     destructor     Destroy; override;
  end;

  // Pipe Server worker thread class
  TPipeServerThread =  class(TPipeThread)
  private
     // Private declarations
     FNotify:       HWND;
     FPipe:         HPIPE;
     FErrorCode:    Integer;
     FPipeServer:   TPipeServer;
     FWrite:        DWORD;
     FPipeWrite:    PPipeWrite;
     FRcvRead:      DWORD;
     FPendingRead:  Boolean;
     FPendingWrite: Boolean;
     FRcvStream:    TMemoryStream;
     FRcvBuffer:    PChar;
     FRcvSize:      DWORD;
     FEvents:       Array [0..3] of THandle;
     FOlapRead:     TOverlapped;
     FOlapWrite:    TOverlapped;
  protected
     // Protected declarations
     function       QueuedRead: Boolean;
     function       CompleteRead: Boolean;
     function       QueuedWrite: Boolean;
     function       CompleteWrite: Boolean;
     procedure      DoMessage;
     procedure      DoDequeue;
     procedure      Execute; override;
  public
     // Public declarations
     constructor    Create(PipeServer: TPipeServer; Pipe: HPIPE; KillEvent, DataEvent: THandle);
     destructor     Destroy; override;
     property       Pipe: HPIPE read FPipe;
  end;

  // Pipe info record stored by the TPipeServer component for each working thread
  PPipeInfo         =  ^TPipeInfo;
  TPipeInfo         =  packed record
     Pipe:          HPIPE;
     WriteQueue:    TWriteQueue;
  end;

  // Pipe context for error messages
  TPipeContext      =  (pcListener, pcWorker);

  // Pipe Events
  TOnPipeConnect    =  procedure(Sender: TObject; Pipe: HPIPE) of object;
  TOnPipeDisconnect =  procedure(Sender: TObject; Pipe: HPIPE) of object;
  TOnPipeMessage    =  procedure(Sender: TObject; Pipe: HPIPE; Stream: TStream) of object;
  TOnPipeSent       =  procedure(Sender: TObject; Pipe: HPIPE; Size: DWORD) of object;
  TOnPipeError      =  procedure(Sender: TObject; Pipe: HPIPE; PipeContext: TPipeContext; ErrorCode: Integer) of object;
  TOnServerStopped  =  procedure(Sender: TObject) of object;

  // Pipe Server component
  TPipeServer       =  class(TObject)
  private
     // Private declarations
     FHwnd:         HWND;
     FPipeName:     string;
     FActive:       Boolean;
     FInShutDown:   Boolean;
     FKillEv:       THandle;
     FClients:      TList;
     FListener:     TPipeListenThread;
     FMustBeFirstInstance:Boolean;
     FThreadCount:  Integer;
     FCritical:     TRTLCriticalSection;
     FSA:           TSecurityAttributes;
     FOPS:          TOnPipeSent;
     FOPC:          TOnPipeConnect;
     FOPD:          TOnPipeDisconnect;
     FOPM:          TOnPipeMessage;
     FOPE:          TOnPipeError;
     FOnStopped:    TOnServerStopped;
     procedure      DoStartup;
     procedure      DoShutdown;
  protected
     // Protected declarations
     function       Dequeue(Pipe: HPIPE): PPipeWrite;
     function       GetClient(Index: Integer): HPIPE;
     function       GetClientCount: Integer;
     procedure      WndMethod(var Message: TMessage);
     procedure      RemoveClient(Pipe: HPIPE);
     procedure      SetActive(Value: Boolean);
     procedure      SetPipeName(const Value: string);
     procedure      AddWorkerThread(Pipe: HPIPE);
     procedure      RemoveWorkerThread(Sender: TObject);
     procedure      RemoveListenerThread(Sender: TObject);
  public
     // Public declarations
     constructor    Create;
     destructor     Destroy; override;
     function       Write(Pipe: HPIPE; const Buffer; Count: Integer): Boolean;
     function       GetFullPipeName: string;
     property       WindowHandle: HWND read FHwnd;
     property       ClientCount: Integer read GetClientCount;
     property       Clients[Index: Integer]: HPIPE read GetClient;
     function       Broadcast(const Buffer; Count: Integer): Boolean;
     function       FindClientNumForPipe(const p:HPIPE): Integer;
     procedure      ClearWriteQueues;
     procedure      WaitUntilWriteQueuesEmpty(const MaxWaitSecs:Integer);
     procedure      LimitWriteQueues(const Limit:Integer);
     function       PipeCreatedOK:Boolean;
     procedure      WaitUntilActive(const ms:Integer);
     property       Active: Boolean read FActive write SetActive;
     property       OnPipeSent: TOnPipeSent read FOPS write FOPS;
     property       OnPipeConnect: TOnPipeConnect read FOPC write FOPC;
     property       OnPipeDisconnect: TOnPipeDisconnect read FOPD write FOPD;
     property       OnPipeMessage: TOnPipeMessage read FOPM write FOPM;
     property       OnPipeError: TOnPipeError read FOPE write FOPE;
     property       OnServerStopped: TOnServerStopped read FOnStopped write FOnStopped;
     property       PipeName: string read FPipeName write SetPipeName;
     property       MustBeFirstInstance: Boolean read FMustBeFirstInstance write FMustBeFirstInstance;
     property       Listener:TPipeListenThread read FListener;
  end;

  // Pipe Client worker thread class
  TPipeClientThread =  class(TPipeThread)
  private
     // Private declarations
     FNotify:       HWND;
     FPipe:         HPIPE;
     FErrorCode:    Integer;
     FPipeClient:   TPipeClient;
     FWrite:        DWORD;
     FPipeWrite:    PPipeWrite;
     FRcvRead:      DWORD;
     FPendingRead:  Boolean;
     FPendingWrite: Boolean;
     FRcvStream:    TMemoryStream;
     FRcvBuffer:    PChar;
     FRcvSize:      DWORD;
     FEvents:       Array [0..3] of THandle;
     FOlapRead:     TOverlapped;
     FCanTerminateAndFree:Boolean;
     FOlapWrite:    TOverlapped;
  protected
     // Protected declarations
     function       QueuedRead: Boolean;
     function       CompleteRead: Boolean;
     function       QueuedWrite: Boolean;
     function       CompleteWrite: Boolean;
     procedure      DoMessage;
     procedure      DoDequeue;
     procedure      Execute; override;
  public
     // Public declarations
     constructor    Create(PipeClient: TPipeClient; Pipe: HPIPE; KillEvent, DataEvent: THandle);
     destructor     Destroy; override;
     property CanTerminateAndFree:Boolean read FCanTerminateAndFree write FCanTerminateAndFree;
  end;

  // Pipe Client component
  TPipeClient       =  class(TObject)
  private
     // Private declarations
     FHwnd:         HWND;
     FPipe:         HPIPE;
     FPipeName:     string;
     FServerName:   string;
     FConnected:    Boolean;
     FWriteQueue:   TWriteQueue;
     FWorker:       TPipeClientThread;
     FKillEv:       THandle;
     FSA:           TSecurityAttributes;
     FOPE:          TOnPipeError;
     FOPD:          TOnPipeDisconnect;
     FOPM:          TOnPipeMessage;
     FOPS:          TOnPipeSent;
     FCritical:     TRTLCriticalSection;
     ReturnValue:   Integer;
     FDestroying:   Boolean;
     InConnect:     Boolean;
  protected
     // Protected declarations
     procedure      SetPipeName(const Value: string);
     procedure      SetServerName(const Value: string);
     function       Dequeue: PPipeWrite;
     procedure      RemoveWorkerThread(Sender: TObject);
     procedure      WndMethod(var Message: TMessage);
  public
     // Public declarations
     FullPipeName:  string;
     constructor    Create;
     destructor     Destroy; override;
     function       Connect(const wait_ms:Integer): Boolean;
     procedure      Disconnect(const CanWait:Boolean);
     procedure      WaitUntilWriteQueueEmpty(const MaxWaitSecs:Integer);
     function       Write(const Buffer; Count: Integer): Boolean;
     function       Busy:Boolean;
     property       Connected: Boolean read FConnected;
     property       WindowHandle: HWND read FHwnd;
     property       Pipe:HPIPE read FPipe;
     property       PipeName: string read FPipeName write SetPipeName;
     property       ServerName: string read FServerName write SetServerName;
     property       OnPipeDisconnect: TOnPipeDisconnect read FOPD write FOPD;
     property       OnPipeMessage: TOnPipeMessage read FOPM write FOPM;
     property       OnPipeSent: TOnPipeSent read FOPS write FOPS;
     property       OnPipeError: TOnPipeError read FOPE write FOPE;
  end;

// Pipe write helper functions
function   AllocPipeWrite(const Buffer; Count: Integer): PPipeWrite;
procedure  DisposePipeWrite(PipeWrite: PPipeWrite);
procedure  CheckPipeName(Value: String);

// Security helper functions
procedure  InitializeSecurity(var SA: TSecurityAttributes);
procedure  FinalizeSecurity(var SA: TSecurityAttributes);

{$endif}

implementation

threadvar isMainThread:Boolean;

{$ifdef MSWINDOWS}

var PCTNUM:Integer;

var ValidObjects:TList;
    VOCrit:TCriticalSection;
    InvalidCounter:Integer;

procedure AddValidObject(const p:Pointer);
begin
  if not Assigned(ValidObjects) then
     Exit;
  VOCrit.Enter;
  try
    ValidObjects.Add(p);
    finally
      VOCrit.Leave;
    end;
  end;

function IsValidObject(const p:Pointer):Boolean;
begin
  Result:=false;
  if not Assigned(p) or not Assigned(ValidObjects) then
     Exit;
  VOCrit.Enter;
  try
    Result:=ValidObjects.IndexOf(p)>=0;
    if not Result then
       Inc(InvalidCounter);
    finally
      VOCrit.Leave;
    end;
  end;

procedure RemoveValidObject(const p:Pointer);
begin
  if not Assigned(ValidObjects) then
     Exit;
  VOCrit.Enter;
  try
    if DebugHook<>0 then
       if not isValidObject(p) then
          raise Exception.Create('Removing invalid object');
    ValidObjects.Remove(p);
    finally
      VOCrit.Leave;
    end;
  end;

procedure InitValidObjects;
begin
  if Assigned(ValidObjects) then
     Exit;
  VOCrit:=TCriticalSection.Create;
  ValidObjects:=TList.Create;
  InvalidCounter:=0;
  end;

procedure FinalizeValidObjects;
begin
  VOCrit.Enter;
  FreeAndNil(ValidObjects);
  VOCrit.Leave;
  FreeAndNil(VOCrit);
  end;


function Bool2S(const b:Boolean):string;
begin
  if b then
     Result:='true'
  else
     Result:='false';
  end;

////////////////////////////////////////////////////////////////////////////////
//
//   TPipeClient
//
////////////////////////////////////////////////////////////////////////////////
constructor TPipeClient.Create;
begin
  // Perform inherited
  inherited Create;

  if not isMainThread then
     raise Exception.Create('Must be in main thread to create a TPipeClient.');

  // Set properties
  InitializeSecurity(FSA);
  FKillEv:=CreateEvent(@FSA, True, False, nil);
  FPipe:=INVALID_HANDLE_VALUE;
  FConnected:=False;
  FWriteQueue:=TWriteQueue.Create;
  FWorker:=nil;
  FPipeName:='PipeServer';
  FServerName:='';
  FHwnd:=AllocateHWnd(WndMethod);

  InitializeCriticalSection(FCritical);
  AddValidObject(self);
  end;

destructor TPipeClient.Destroy;
begin
  if not isMainThread then
     raise Exception.Create('Must be in main thread to destroy a TPipeClient (Pipe:'+FPipeName+', Server:'+FServerName+').');

  if not Assigned(self) or not IsValidObject(self) then
     Exit;

  FDestroying:=true;

  RemoveValidObject(self);

  if Assigned(FWorker) and IsValidObject(FWorker) then begin // TG 2013 !!!
     FWorker.OnTerminate:=nil;
     FWorker.FPipeClient:=nil;
     end;

  // Disconnect if connected
  Disconnect(false);

  // Free resources
  FinalizeSecurity(FSA);
  CloseHandle(FKillEv);
  FWriteQueue.Free;
  if FHwnd<>0 then
     DeAllocateHWnd(FHwnd);
  FHwnd:=0;
  DeleteCriticalSection(FCritical);

  // Perform inherited
  inherited Destroy;
  end;

function TPipeClient.Connect(const wait_ms:Integer): Boolean;
var  szname:     String;
     lpname:     Array [0..1023] of Char;
     resolved:   Boolean;
     dwmode:     DWORD;
     dwSize:     DWORD;
begin
  if InConnect then begin
     Result:=FConnected;
     Exit;
     end;
  InConnect:=true;
  try
    // Optimistic result
    result:=True;

    // Exit if already connected
    if FConnected then exit;

    {$ifdef EXTENDEDLOGGING}
    if Assigned(PipesLogProc) then PipesLogProc('PipeClient.Connect: '+FPipeName);
    {$endif}
    // Set server name resolution
    resolved:=False;

    // Check name against local computer name first
    dwSize:=SizeOf(lpname);
    if GetComputerName(lpname, dwSize) then
    begin
       // Compare names
       if (CompareText(lpname, FServerName) = 0) then
       begin
          // Server name represents local computer, switch to the
          // preferred use of "." for the name
          szname:='.';
          resolved:=True;
       end;
    end;

    // Resolve the server name
    if not(resolved) then
    begin
       // Blank name also indicates local computer
       if (FServerName = '') then
          szname:='.'
       else
          szname:=FServerName;
    end;

    // Build the full pipe name
    FullPipeName:=Format('\\%s\pipe\%s', [szname, string(FPipeName)]);
    StrCopy(lpname, PChar(string(FullPipeName)));

    // Attempt to wait for the pipe first
    if WaitNamedPipe(PChar(@lpname), wait_ms) then
    begin
       // Attempt to create client side handle
       FPipe:=CreateFile(PChar(@lpname), GENERIC_READ or GENERIC_WRITE, 0, @FSA, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL or FILE_FLAG_OVERLAPPED, 0);
       // Success if we have a valid handle
       result:=(FPipe <> INVALID_HANDLE_VALUE);
       // Need to set message mode
       if result then
       begin
          dwmode:=PIPE_READMODE_MESSAGE or PIPE_WAIT;
          SetNamedPipeHandleState(FPipe, dwmode, nil, nil);
          // Create thread to handle the pipe IO
          FWorker:=TPipeClientThread.Create(Self, FPipe, FKillEv, FWriteQueue.DataEvent);
          FWorker.OnTerminate:=RemoveWorkerThread;
       end;
    end
    else
       // Failure
       result:=False;

    // Set connected flag
    FConnected:=result;
    {$ifdef EXTENDEDLOGGING}
    if Assigned(PipesLogProc) then
       PipesLogProc('PipeClient.Connect Result: '+FPipeName+IntToStr(ord(Result)));
    {$endif}
    finally
      InConnect:=false;
    end;
  end;

procedure TPipeClient.Disconnect(const CanWait:Boolean);
var i:Integer;
    MyWorker:TPipeClientThread;
begin
  if not Assigned(self) then begin
     if DebugHook<>0 then
        raise Exception.Create('nil');
     Exit;
     end;

  // Exit if not connected
  if not FConnected then begin
     if DebugHook<>0 then
        FConnected:=false;
     Exit;
     end;

  {$ifdef EXTENDEDLOGGING}
  if Assigned(PipesLogProc) then PipesLogProc('PipeClient.Disconnect: '+FPipeName+' CanWait: '+IntToStr(ord(CanWait)));
  {$endif}

  // Signal the kill event
  SetEvent(FKillEv);

  // make local copy of FWorker, because FWorker is set to nil by the thread, OMFG!
  EnterCriticalSection(FCritical);
  try
    MyWorker:=FWorker;
    // this is thread safe: while we are in FCritical,
    // "RemoveWorkerThread" cannot set FWorker to nil,
    // and the worker thread cannot free itself,
    // (unless it has done so before, and then MyWorker is nil)
    // because the threading library is calling RemoveWorkerThread via Synchronize
    if Assigned(MyWorker) then begin
       MyWorker.FCanTerminateAndFree:=false;
       try
         MyWorker.Terminate;
         except
         end;
       end;
    finally
      LeaveCriticalSection(FCritical);
    end;

  // wait for the worker thread to finish
  if Assigned(MyWorker) then begin
     if CanWait then begin
        while MyWorker.ReturnValue=0 do begin
          // MUST PROCESS MESSAGES OR THIS WILL HANG FOREVER
          Forms.Application.ProcessMessages;
          sleep(50);
          end;
        end;

     MyWorker.FCanTerminateAndFree:=true;
     if not MyWorker.FreeOnTerminate then
        FreeAndNil(MyWorker);
     end;

  // Set new state
  FConnected:=False;
  end;

function TPipeClient.Write(const Buffer; Count: Integer): Boolean;
begin
  // Set default result (depends on connected state)
  if not Assigned(self) then begin
     Result:=false;
     Exit;
     end;
  result:=FConnected;

  // Exit if not connected
  if not result then
     exit;

  // Enqueue the data
  FWriteQueue.Enqueue(AllocPipeWrite(Buffer, Count));
  end;

procedure TPipeClient.SetPipeName(const Value: string);
begin

  // Raise error if pipe is connected
  if FConnected then raise EPipeException.CreateRes(PResStringRec(@resPipeConnected));

  // Check the pipe name
  CheckPipeName(Value);

  // Set the pipe name
  FPipeName:=Value;

end;

procedure TPipeClient.SetServerName(const Value: string);
begin

  // Raise error if pipe is connected
  if FConnected then raise EPipeException.CreateRes(PResStringRec(@resPipeConnected));

  // Set the server name
  FServerName:=Value;

end;

function TPipeClient.Dequeue: PPipeWrite;
begin
  // Dequeue the record and break
  result:=FWriteQueue.Dequeue;
  end;

procedure TPipeClient.RemoveWorkerThread(Sender: TObject);
var LWorker:TPipeClientThread;
begin
  if not IsValidObject(self) or
     not IsValidObject(Sender) then
     Exit;
  if (Sender as TPipeClientThread).FPipeClient=nil then begin
     if isMainThread and (DebugHook<>0) then
        isMainThread:=true;
     Exit;
     end;
  if (ord(FConnected)=0) then
     if not Assigned(FWorker) then // TG 2013
        Exit
     else
       // OK, proceed
  else
  if (ord(FConnected)<>1) then begin
     if (DebugHook<>0) then
        raise Exception.Create('TPipeClient already freed');
     Exit;
     end;
  // Resource protection
  try
     // Clear the thread object first
     EnterCriticalSection(FCritical);
     try
       LWorker:=FWorker;
       FWorker:=nil;
       finally
         LeaveCriticalSection(FCritical);
       end;
     // Call the OnPipeDisconnect if not in a destroying state
     if not FDestroying and Assigned(FOPD) then
        FOPD(Self, FPipe);
  finally
     // Invalidate the pipe handle
     FPipe:=INVALID_HANDLE_VALUE;
     // Set state to disconneted
     FConnected:=False;
  end;

  if Assigned(LWorker) then
     while not LWorker.CanTerminateAndFree do
       if isMainThread then begin
          LWorker.FreeOnTerminate:=false; // cannot loop/hang main thread, so we risk a memory leak
          break;
          end
       else
          sleep(1);
end;


procedure TPipeClient.WaitUntilWriteQueueEmpty(const MaxWaitSecs: Integer);
var waitcounter,index:Integer;
    AllEmpty:Boolean;
begin
  waitcounter:=0;
  repeat
    AllEmpty:=false;
    try
      AllEmpty:=FWriteQueue.GetCount=0;
      except
      end;
    if AllEmpty then
       break;
    if waitcounter>=MaxWaitSecs*20 then
       break;
    Forms.Application.ProcessMessages;
    sleep(50);
    Inc(waitcounter);
    until not IsValidObject(self);
  end;

procedure TPipeClient.WndMethod(var Message: TMessage);
var  MemStream:  TMemoryStream;
     lpmsg:      PChar;
     dwmem:      Integer;
begin
  if not IsValidObject(self) then
     Exit;

  // Handle the pipe messages
  case Message.Msg of
     WM_QUERYENDSESSION:  Message.Result:=1;
     WM_PIPEERROR_W    :  if Assigned(FOPE) then
                             FOPE(Self, Message.wParam, pcWorker, Message.lParam);
     WM_PIPEDISCONNECT :  if Assigned(FOPD) then
                             FOPD(Self, Message.wParam);
     WM_PIPESEND       :  if Assigned(FOPS) then
                             FOPS(Self, Message.wParam, Message.lParam);
     WM_PIPEMESSAGE    :
     begin
        dwmem:=GlobalSize(Message.lParam);
        if (dwmem > 0) then
        begin
           MemStream:=TMemoryStream.Create;
           lpmsg:=GlobalLock(Message.lParam);
           try
              // Copy the actual stream contents over
              MemStream.Write(lpmsg^, dwmem);
              MemStream.Position:=0;
              // Call the OnMessage event if assigned
              if Assigned(FOPM) then
                 FOPM(Self, Message.wParam, MemStream);
           finally
              MemStream.Free;
              GlobalUnLock(Message.lParam);
           end;
        end;
        GlobalFree(Message.lParam);
     end;
  else
     // Call default window procedure
     DefWindowProc(FHwnd, Message.Msg, Message.wParam, Message.lParam);
  end;

end;

////////////////////////////////////////////////////////////////////////////////
//
//   TPipeClientThread
//
////////////////////////////////////////////////////////////////////////////////
constructor TPipeClientThread.Create(PipeClient: TPipeClient; Pipe: HPIPE; KillEvent, DataEvent: THandle);
begin
  // Set starting parameters
  FreeOnTerminate:=True;
  FPipe:=Pipe;
  FPipeClient:=PipeClient;
  FNotify:=PipeClient.WindowHandle;
  FErrorCode:=ERROR_SUCCESS;
  FPendingRead:=False;
  FPendingWrite:=False;
  FPipeWrite:=nil;
  FRcvSize:=MIN_BUFFER;
  FRcvBuffer:=AllocMem(FRcvSize);
  FRcvStream:=TMemoryStream.Create;
  FCanTerminateAndFree:=true;
  FOlapRead.Offset:=0;
  FOlapRead.OffsetHigh:=0;
  FOlapRead.hEvent:=CreateEvent(nil, True, False, nil);
  FOlapWrite.hEvent:=CreateEvent(nil, True, False, nil);
  ResetEvent(KillEvent);
  FEvents[0]:=KillEvent;
  FEvents[1]:=FOlapRead.hEvent;
  FEvents[2]:=FOlapWrite.hEvent;
  FEvents[3]:=DataEvent;
  
  // Perform inherited
  if (PipeClient.PipeName='') then
     if DebugHook<>0 then
        raise Exception.Create('PipeClient.Name=''''');
  Inc(PCTNUM);
  inherited Create(False{$ifdef USETGTHREADS},
            'PipeClientThread #'+SysUtils.IntToStr(PCTNUM)+' for '+PipeClient.PipeName{$endif});
  AddValidObject(self);
  end;

destructor TPipeClientThread.Destroy;
begin
  if not Assigned(self) or not IsValidObject(self) then
     Exit;

  RemoveValidObject(self);
  // Free the write buffer we may be holding on to
  if FPendingWrite and Assigned(FPipeWrite) then DisposePipeWrite(FPipeWrite);

  // Free the receiver stream and buffer memory
  FreeMem(FRcvBuffer);
  FRcvStream.Free;

  // Perform inherited
  inherited Destroy;
  end;

function TPipeClientThread.QueuedRead: Boolean;
var  bRead:      Boolean;
begin

  // Set default result
  result:=True;

  // If we already have a pending read then nothing to do
  if not (FPendingRead) then begin
     // Set defaults for reading
     FRcvStream.Clear;
     FRcvSize:=MIN_BUFFER;
     ReAllocMem(FRcvBuffer, FRcvSize);
     // Keep reading all available data until we get a pending read or a failure
     while IsValidObject(self) and result and not (FPendingRead) do begin
        // Perform a read
        bRead:=ReadFile(FPipe, FRcvBuffer^, FRcvSize, FRcvRead, @FOlapRead);
        // Get the last error code
        FErrorCode:=GetLastError;
        // Check the read result
        if bRead then begin
           {$ifdef EXTENDEDLOGGING}
           if Assigned(PipesLogProc) then
              PipesLogProc('Pipe Client Small Msg Received');
           {$endif}
           // We read a full message
           FRcvStream.Write(FRcvBuffer^, FRcvRead);
           // Call the OnData
           DoMessage;
           end
        else begin
           {$ifdef EXTENDEDLOGGING}
           if Assigned(PipesLogProc) then
              PipesLogProc('Pipe Client Msg Received, Result Code='+IntToStr(FErrorCode));
           {$endif}
           // Handle cases where message is larger than read buffer used
           if (FErrorCode = ERROR_MORE_DATA) then begin
              // Write the current data
              FRcvStream.Write(FRcvBuffer^, FRcvSize);
              // Determine how much we need to expand the buffer to
              if PeekNamedPipe(FPipe, nil, 0, nil, nil, @FRcvSize) then begin
                 {$ifdef EXTENDEDLOGGING}
                 if Assigned(PipesLogProc) then
                    PipesLogProc('Pipe Client Buf Size needs to be '+IntToStr(FRcvSize));
                 {$endif}
                 ReallocMem(FRcvBuffer, FRcvSize);
                 end
              else begin
                 // Failure
                 FErrorCode:=GetLastError;
                 {$ifdef EXTENDEDLOGGING}
                 if Assigned(PipesLogProc) then
                    PipesLogProc('Pipe Client Peek Result Code='+IntToStr(FErrorCode));
                 {$endif}
                 result:=False;
                 end;
              end
           // Pending read
           else if (FErrorCode = ERROR_IO_PENDING) then
              // Set pending flag
              FPendingRead:=True
           else
              // Failure
              result:=False;
           end;
        end;
     end;
  end;

function TPipeClientThread.CompleteRead: Boolean;
begin

  // Reset the read event and pending flag
  ResetEvent(FOlapRead.hEvent);

  // Check the overlapped results
  result:=GetOverlappedResult(FPipe, FOlapRead, FRcvRead, True);

  // Handle failure
  if not(result) then
  begin
     // Get the last error code
     FErrorCode:=GetLastError;
     // Check for more data
     if (FErrorCode = ERROR_MORE_DATA) then
     begin
        // Write the current data
        FRcvStream.Write(FRcvBuffer^, FRcvSize);
        // Determine how much we need to expand the buffer to
        result:=PeekNamedPipe(FPipe, nil, 0, nil, nil, @FRcvSize);
        if result then
        begin
           // Realloc mem to read in rest of message
           ReallocMem(FRcvBuffer, FRcvSize);
           // Read from the file again
           result:=ReadFile(FPipe, FRcvBuffer^, FRcvSize, FRcvRead, @FOlapRead);
           // Handle error
           if not(result) then
           begin
              // Set error code
              FErrorCode:=GetLastError;
              // Check for pending again, which means our state hasn't changed
              if (FErrorCode = ERROR_IO_PENDING) then
              begin
                 // Bail out and wait for this operation to complete
                 result:=True;
                 exit;
              end;
           end;
        end
        else
           // Set error code
           FErrorCode:=GetLastError;
     end;
  end;

  // Handle success
  if result then
  begin
     // We read a full message
     FRcvStream.Write(FRcvBuffer^, FRcvRead);
     // Call the OnData 
     DoMessage;
     // Reset the pending read
     FPendingRead:=False;
  end;

end;

function TPipeClientThread.QueuedWrite: Boolean;
var  bWrite:      Boolean;
begin
  // Set default result
  result:=True;

  // If we already have a pending write then nothing to do
  if not(FPendingWrite) then
  begin
     // Check state of data event
     if (WaitForSingleObject(FEvents[3], 0) = WAIT_OBJECT_0) then
     begin
        // Pull the data from the queue
        DoDequeue; // now thread safe, no more Synchronize call necessary
        // Is the record assigned?
        if Assigned(FPipeWrite) then
        begin
           // Write the data to the client
           bWrite:=WriteFile(FPipe, FPipeWrite^.Buffer^, FPipeWrite^.Count, FWrite, @FOlapWrite);
           // Get the last error code
           FErrorCode:=GetLastError;
           // Check the write operation
           if bWrite then
           begin
              // Call the OnData in the main thread
              PostMessage(FNotify, WM_PIPESEND, FPipe, FWrite);
              // Free the pipe write data
              DisposePipeWrite(FPipeWrite);
              FPipeWrite:=nil;
              // Reset the write event
              ResetEvent(FOlapWrite.hEvent);
           end
           else
           begin
              // Only acceptable error is pending
              if (FErrorCode = ERROR_IO_PENDING) then
                 // Set pending flag
                 FPendingWrite:=True
              else
                 // Failure
                 result:=False;
           end;
        end;
     end;
  end;

end;

function TPipeClientThread.CompleteWrite: Boolean;
begin

  // Reset the write event and pending flag
  ResetEvent(FOlapWrite.hEvent);

  // Check the overlapped results
  result:=GetOverlappedResult(FPipe, FOlapWrite, FWrite, True);

  // Handle failure
  if not(result) then
     // Get the last error code
     FErrorCode:=GetLastError
  else
     // We sent a full message so call the OnSent in the main thread
     PostMessage(FNotify, WM_PIPESEND, FPipe, FWrite);

  // We are done either way. Make sure to free the queued pipe data
  // and to reset the pending flag
  if Assigned(FPipeWrite) then
  begin
     DisposePipeWrite(FPipeWrite);
     FPipeWrite:=nil;
  end;
  FPendingWrite:=False;

end;

procedure TPipeClientThread.DoDequeue;
begin
  // Get the next queued data event
  if Assigned(FPipeClient) then
     FPipeWrite:=FPipeClient.Dequeue
  else
     FPipeWrite:=nil;
  end;

procedure TPipeClientThread.DoMessage;
var  lpmem:      THandle;
     lpmsg:      PChar;
begin

  // Convert the memory to global memory and send to pipe server
  lpmem:=GlobalAlloc(GHND, FRcvStream.Size);
  lpmsg:=GlobalLock(lpmem);

  // Copy from the pipe
  FRcvStream.Position:=0;
  FRcvStream.Read(lpmsg^, FRcvStream.Size);

  // Unlock the memory
  GlobalUnlock(lpmem);

  // Send to the pipe server to manage
  PostMessage(FNotify, WM_PIPEMESSAGE, FPipe, lpmem);

  // Clear the read stream
  FRcvStream.Clear;

end;

procedure TPipeClientThread.Execute;
var  dwEvents:   Integer;
     bOK:        Boolean;
begin
  ReturnValue:=0;
  if Assigned(FPipeClient) then
     FPipeClient.ReturnValue:=0;
  // Loop while not terminated
  while IsValidObject(self) and not(Terminated) do
  begin
     // Make sure we always have an outstanding read and write queued up
     bOK:=(QueuedRead and QueuedWrite);
     if bOK then
     begin
        // If we are in a pending write then we need will not wait for the
        // DataEvent, because we are already waiting for a write to finish
        dwEvents:=4;
        if FPendingWrite then Dec(dwEvents);
        // Handle the event that was signalled (or failure)
        case WaitForMultipleObjects(dwEvents, PWOHandleArray(@FEvents), False, INFINITE) of
           // Killed by pipe server
           WAIT_OBJECT_0     :  Terminate;
           // Read completed
           WAIT_OBJECT_0+1   :  bOK:=CompleteRead;
           // Write completed
           WAIT_OBJECT_0+2   :  bOK:=CompleteWrite;
           // Data waiting to be sent
           WAIT_OBJECT_0+3   :  ; // Data available to write
        else
           // General failure
           FErrorCode:=GetLastError;
           bOK:=False;
        end;
     end;
     // Check status
     if not(bOK) then
     begin
        // Call OnError in the main thread if this is not a disconnect. Disconnects
        // have their own event, and are not to be considered an error
        if (FErrorCode <> ERROR_PIPE_NOT_CONNECTED) then
           PostMessage(FNotify, WM_PIPEERROR_W, FPipe, FErrorCode);
        // Terminate
        Terminate;
     end;
  end;

  // Make sure the handle is still valid
  if (FErrorCode <> ERROR_INVALID_HANDLE) then
  begin
     DisconnectNamedPipe(FPipe);
     CloseHandle(FPipe);
  end;

  // Close all open handles that we own
  CloseHandle(FOlapRead.hEvent);
  CloseHandle(FOlapWrite.hEvent);

  ReturnValue:=1;
  if Assigned(FPipeClient) then
     FPipeClient.ReturnValue:=1;
  while not CanTerminateAndFree do
    sleep(10);
  end;

////////////////////////////////////////////////////////////////////////////////
//
//   TServerPipe
//
////////////////////////////////////////////////////////////////////////////////
procedure TPipeServer.ClearWriteQueues;
var  index:      Integer;
     ppiClient:  PPipeInfo;
begin
  EnterCriticalSection(FCritical);
  try
    for index:=FClients.Count-1 downto 0 do begin
       try
         ppiClient:=FClients[index];
         ppiClient.WriteQueue.Clear;
         except
         end;
       end;
    finally
      LeaveCriticalSection(FCritical);
    end;
  end;

procedure TPipeServer.WaitUntilActive(const ms: Integer);
var i:Integer;
begin
  i:=0;
  while not PipeCreatedOK do begin
    Forms.Application.ProcessMessages;
    sleep(50);
    Inc(i);
    if i*50>ms then
       break;
    Forms.Application.ProcessMessages;
    end;
  end;

procedure TPipeServer.WaitUntilWriteQueuesEmpty(const MaxWaitSecs:Integer);
var waitcounter,index:      Integer;
    ppiClient:  PPipeInfo;
    AllEmpty:Boolean;
begin
  waitcounter:=0;
  repeat
    AllEmpty:=true;
    EnterCriticalSection(FCritical);
    try
      for index:=FClients.Count-1 downto 0 do begin
         try
           ppiClient:=FClients[index];
           if ppiClient.WriteQueue.GetCount>0 then begin
              AllEmpty:=false;
              break;
              end;
           except
           end;
         end;
      finally
        LeaveCriticalSection(FCritical);
      end;
    if AllEmpty then
       break;
    if waitcounter>=MaxWaitSecs*20 then
       break;
    Forms.Application.ProcessMessages;
    sleep(50);
    Inc(waitcounter);
    until not IsValidObject(self);
  end;

constructor TPipeServer.Create;
begin
  // Perform inherited
  inherited Create;

  if not isMainThread then
     raise Exception.Create('Must be in main thread to create a TPipeServer.');

  InitializeCriticalSection(FCritical);
  {$ifdef EXTENDEDLOGGING}
  if Assigned(PipesLogProc) then PipesLogProc('TPipeServer.Create');
  {$endif}

  // Initialize the security attributes
  InitializeSecurity(FSA);

  // Set staring defaults
  FPipeName:='PipeServer';
  FActive:=False;
  FInShutDown:=False;
  FKillEv:=CreateEvent(@FSA, True, False, nil);
  FClients:=TList.Create;
  FListener:=nil;
  FThreadCount:=0;
  FHwnd:=AllocateHWnd(WndMethod);
  AddValidObject(self);
  end;

destructor TPipeServer.Destroy;
begin
  if not isMainThread then
     raise Exception.Create('Must be in main thread to destroy a TPipeServer  (Pipe:'+FPipeName+').');

  if not Assigned(self) or not IsValidObject(self) then
     Exit;

  // Perform the shutdown if active
  if FActive then
     DoShutdown;

  {$ifdef EXTENDEDLOGGING}
  if Assigned(PipesLogProc) then PipesLogProc('TPipeServer.Destroy '+FPipeName);
  {$endif}

  // Release all objects, events, and handles
  CloseHandle(FKillEv);
  EnterCriticalSection(FCritical);
  try
    FreeAndNil(FClients);
    finally
      LeaveCriticalSection(FCritical);
    end;
  FinalizeSecurity(FSA);

  // Close the window
  if FHwnd<>0 then
     DeAllocateHWnd(FHwnd);
  FHwnd:=0;
  RemoveValidObject(self);
  DeleteCriticalSection(FCritical);

  // Perform inherited
  inherited Destroy;
  end;

procedure TPipeServer.WndMethod(var Message: TMessage);
var  MemStream:  TMemoryStream;
     lpmsg:      PChar;
     dwmem:      Integer;
begin
  if not IsValidObject(self) then
     Exit;
  case Message.Msg of
     WM_QUERYENDSESSION:  Message.Result:=1;
     WM_PIPEERROR_L    :
        if not(FInShutdown) and Assigned(FOPE) then
           FOPE(Self, Message.wParam, pcListener, Message.lParam);
     WM_PIPEERROR_W    :
        if not(FInShutdown) and Assigned(FOPE) then
           FOPE(Self, Message.wParam, pcWorker, Message.lParam);
     WM_PIPECONNECT    :
        if Assigned(FOPC) then
           FOPC(Self, Message.wParam);
     WM_PIPEDISCONNECT :
        if Assigned(FOPD) then
           FOPD(Self, Message.wParam);
     WM_PIPESEND       :
        if Assigned(FOPS) then
           FOPS(Self, Message.wParam, Message.lParam);
     WM_PIPEMESSAGE    :
      begin
        dwmem:=GlobalSize(Message.lParam);
        if (dwmem > 0) then
        begin
           MemStream:=TMemoryStream.Create;
           lpmsg:=GlobalLock(Message.lParam);
           try
              // Copy the actual stream contents over
              MemStream.Write(lpmsg^, dwmem);
              MemStream.Position:=0;
              // Call the OnMessage event if assigned
              if Assigned(FOPM) then
                 FOPM(Self, Message.wParam, MemStream);
           finally
              MemStream.Free;
              GlobalUnLock(Message.lParam);
           end;
        end;
        GlobalFree(Message.lParam);
      end;
  else
     DefWindowProc(FHwnd, Message.Msg, Message.wParam, Message.lParam);
  end;

end;

function TPipeServer.GetClient(Index: Integer): HPIPE;
begin
  Result:=0;
  // Return the requested pipe
  EnterCriticalSection(FCritical);
  try
    if Assigned(FClients) and
       (Index<FClients.Count) then
       result:=PPipeInfo(FClients[Index])^.Pipe;
    finally
      LeaveCriticalSection(FCritical);
    end;
  end;

function TPipeServer.GetClientCount: Integer;
begin
  // Return the number of active clients
  EnterCriticalSection(FCritical);
  try
    if not Assigned(self) or
       not Assigned(FClients) then
       Result:=0
    else
       result:=FClients.Count;
    finally
      LeaveCriticalSection(FCritical);
    end;
  end;

function TPipeServer.GetFullPipeName: string;
begin
  if Assigned(FListener) then
     Result:=FListener.FullPipeName
  else
     Result:='';
  end;

procedure TPipeServer.LimitWriteQueues(const Limit: Integer);
var  index:      Integer;
     ppiClient:  PPipeInfo;
     pw:         PPipeWrite;
begin
  EnterCriticalSection(FCritical);
  try
    for index:=FClients.Count-1 downto 0 do begin
       // Get the pipe record and compare handles
       try
         ppiClient:=FClients[index];
         while ppiClient.WriteQueue.GetCount>Limit do begin
           pw:=ppiClient.WriteQueue.Dequeue;
           {$ifdef EXTENDEDLOGGING}
           if Assigned(PipesLogProc) then
              PipesLogProc('Skipped Sending Data: '+
                       IntToStr(pw.Count)+' bytes.');
           {$endif}
           DisposePipeWrite(pw);
           end;
         except
           // esp. ignore if FClients[index] does not exist due to thread concurrency
         end;
       end;
    finally
      LeaveCriticalSection(FCritical);
    end;
  end;

function TPipeServer.PipeCreatedOK: Boolean;
begin
  PipeCreatedOK:=Assigned(self) and Active and Assigned(FListener) and (FListener.FPipe<>INVALID_HANDLE_VALUE);
  end;

function TPipeServer.Write(Pipe: HPIPE; const Buffer; Count: Integer): Boolean;
var  index:      Integer;
     ppiClient:  PPipeInfo;
begin
  {$IFDEF MEMDEBUG}KMSetThreadMarker('PipSrvW0');{$ENDIF}
  // Set default result
  result:=False;

  {$ifdef EXTENDEDLOGGING}
  if Assigned(PipesLogProc) then PipesLogProc('Write to pipe '+
           IntToStr(Pipe)+': '+IntToStr(Count)+
           ' Bytes, ClientCount='+IntToStr(ClientCount));
  {$endif}
  // Locate the pipe info record for the given pipe first
  ppiClient:=nil;
  EnterCriticalSection(FCritical);
  try
    for index:=FClients.Count-1 downto 0 do begin
       // Get the pipe record and compare handles
       try
         ppiClient:=FClients[index];
         if (ppiClient^.Pipe = Pipe) then
            break;
         ppiClient:=nil;
         except
         end;
       end;

    {$ifdef EXTENDEDLOGGING}
    if not Assigned(ppiClient) then
       if Assigned(PipesLogProc) then PipesLogProc('not found pipe '+
             IntToStr(Pipe)+': '+IntToStr(Count)+
             ' Bytes, ClientCount='+IntToStr(ClientCount));
    {$endif}
    // If client record is nil then raise exception
    if (ppiClient = nil) or (Count > MAX_BUFFER) then exit;

    {$IFDEF MEMDEBUG}KMSetThreadMarker('PipSrvW5');{$ENDIF}
    // Queue the data
    ppiClient.WriteQueue.Enqueue(AllocPipeWrite(Buffer, Count));

    finally
      LeaveCriticalSection(FCritical);
    end;

  {$ifdef EXTENDEDLOGGING}if Assigned(PipesLogProc) then PipesLogProc('PipeServer Enqueuing Data: '+IntToStr(Count)+' bytes.');{$endif}
  result:=True;
  {$IFDEF MEMDEBUG}KMSetThreadMarker('PipSrvWX');{$ENDIF}
  end;

function TPipeServer.Broadcast(const Buffer; Count: Integer): Boolean;
var dwCount:Integer;
begin
  {$IFDEF MEMDEBUG}KMSetThreadMarker('PipSrvB0');{$ENDIF}
  // Default result
  result:=True;

  {$ifdef EXTENDEDLOGGING}
  if Assigned(PipesLogProc) then PipesLogProc('Broadcast: '+IntToStr(Count)+
           ' Bytes, ClientCount='+IntToStr(ClientCount));
  {$endif}

  // Iterate the pipes and write to each one. *** Added by Russell on 01.19.2004 ***

  EnterCriticalSection(FCritical);
  try
    for dwCount:=Pred(ClientCount) downto 0 do begin
       try
         // Fail if a write fails
         {$IFDEF MEMDEBUG}KMSetThreadMarker('PipSrvB1');{$ENDIF}
         result:=Write(Clients[dwCount], Buffer, Count);
         {$IFDEF MEMDEBUG}KMSetThreadMarker('PipSrvB2');{$ENDIF}
         // Break on a failed write
         if not result then
            break;
         except
         end;
       end;
    finally
      LeaveCriticalSection(FCritical);
    end;

  {$IFDEF MEMDEBUG}KMSetThreadMarker('PipSrvBX');{$ENDIF}
  end;

function TPipeServer.Dequeue(Pipe: HPIPE): PPipeWrite;
var  index:      Integer;
     ppiClient:  PPipeInfo;
begin
  // Locate the pipe info record for the given pipe and dequeue the next
  // available record
  result:=nil;
  EnterCriticalSection(FCritical);
  try
    for index:=FClients.Count-1 downto 0 do
       try
         // Get the pipe record and compare handles
         ppiClient:=FClients[index];
         if (ppiClient^.Pipe = Pipe) then begin
            // Found the desired pipe record, dequeue the record and break
            result:=ppiClient.WriteQueue.Dequeue;
            break;
            end;
         except
         end;
    finally
      LeaveCriticalSection(FCritical);
    end;
  end;

procedure TPipeServer.RemoveClient(Pipe: HPIPE);
var  index:      Integer;
     ppiClient:  PPipeInfo;
begin
  {$ifdef EXTENDEDLOGGING}
  if Assigned(PipesLogProc) then
     PipesLogProc('PipeServer.Disconnect pipe '+IntToStr(Pipe));
  {$endif}

  // Locate the pipe info record for the give pipe and remove it
  EnterCriticalSection(FCritical);
  try
    for index:=FClients.Count-1 downto 0 do
       try
         // Get the pipe record and compare handles
         ppiClient:=FClients[index];
         if (ppiClient^.Pipe = Pipe) then begin
            // Found the desired pipe record, free it
            FClients.Delete(index);
            ppiClient.WriteQueue.Free;
            FreeMem(ppiClient);
            // Call the OnDisconnect if assigned and not in a shutdown
            if not(FInShutdown) and Assigned(FOPD) then PostMessage(FHwnd, WM_PIPEDISCONNECT, Pipe, 0);
            // Break the loop
            break;
            end;
         except
         end;
    finally
      LeaveCriticalSection(FCritical);
    end;
  end;

procedure TPipeServer.SetActive(Value: Boolean);
begin
  if not Assigned(self) then
     Exit;
  // Check against current state
  if Assigned(PipesLogProc) then
     PipesLogProc('TPipeServer.SetActive('+Bool2S(Value)+')');
  if (FActive <> Value) then
  begin
     // Shutdown if active
     if FActive then DoShutdown;
     // Startup if not active
     if Value then DoStartup
  end;

end;

procedure TPipeServer.SetPipeName(const Value: string);
begin

  // Cannot change pipe name if pipe server is active
  if FActive then raise EPipeException.CreateRes(PResStringRec(@resPipeActive));

  // Check the pipe name
  CheckPipeName(Value);

  // Set the new pipe name
  FPipeName:=Value;
  end;

procedure TPipeServer.AddWorkerThread(Pipe: HPIPE);
var  ppInfo:        PPipeInfo;
     pstWorker:     TPipeServerThread;
begin
  {$ifdef EXTENDEDLOGGING}
  if Assigned(PipesLogProc) then PipesLogProc('TPipeServer.AddWorkerThread '+FPipeName+' for pipe #'+IntToStr(Pipe));
  {$endif}

  // If there are more than 100 worker threads then we need to
  // suspend the listener thread until our count decreases
  if (FThreadCount > MAX_THREADS) and
     Assigned(FListener) then
     FListener.Suspend;

  // Create a new pipe info structure to manage the pipe
  ppInfo:=AllocMem(SizeOf(TPipeInfo));
  ppInfo^.Pipe:=Pipe;
  ppInfo^.WriteQueue:=TWriteQueue.Create;

  // Add the structure to the list of pipes
  EnterCriticalSection(FCritical);
  try
    FClients.Add(ppInfo);
    finally
      LeaveCriticalSection(FCritical);
    end;

  // Resource protection
  pstWorker:=nil;
  try
     // Create the server worker thread
     Inc(FThreadCount);
     pstWorker:=TPipeServerThread.Create(Self, Pipe, FKillEv, ppInfo^.WriteQueue.DataEvent);
     pstWorker.OnTerminate:=RemoveWorkerThread;
  except
    {$ifdef EXTENDEDLOGGING}
    if Assigned(PipesLogProc) then PipesLogProc('TPipeServer.AddWorkerThread exception');
    {$endif}
     // Exception during thread create, remove the client record
     RemoveClient(Pipe);
     // Disconnect and close the pipe handle
     DisconnectNamedPipe(Pipe);
     CloseHandle(Pipe);
     FreeAndNil(pstWorker);
     // Decrement the thread count
     Dec(FThreadCount);
  end;
  {$ifdef EXTENDEDLOGGING}
  if Assigned(PipesLogProc) then PipesLogProc('TPipeServer.AddWorkerThread done');
  {$endif}
end;

procedure TPipeServer.RemoveWorkerThread(Sender: TObject);
begin
  {$ifdef EXTENDEDLOGGING}
  if Assigned(PipesLogProc) then PipesLogProc('TPipeServer.RemoveWorkerThread '+FPipeName);
  {$endif}
  if not IsValidObject(self) or
     not IsValidObject(Sender) then
     Exit;
  // Remove the pipe info record associated with this thread
  RemoveClient(TPipeServerThread(Sender).Pipe);

  // Decrement the thread count
  Dec(FThreadCount);

  // *** Added shutdown check by Adam on 01.19.2004 ***
  // If there are less than the maximum worker threads then we need to
  // resume the listener thread
  if FActive and not FInShutdown and
     (FThreadCount < MAX_THREADS) and
     Assigned(FListener) and
     FListener.Suspended then begin
     FListener.Resume;
     end;
end;

procedure TPipeServer.RemoveListenerThread(Sender: TObject);
begin
  {$ifdef EXTENDEDLOGGING}
  if Assigned(PipesLogProc) then PipesLogProc('TPipeServer.RemoveListenerThread '+FPipeName);
  {$endif}
  if not IsValidObject(self) then
     Exit;
  // Decrement the thread count
  Dec(FThreadCount);

  // Clear the listener *** Added by Russell on 01.19.2004 ***
  FListener:=nil;

  // If we not in a shutdown, and we were the only thread, then
  // change the active state
  if (not(FInShutDown) and
     (FThreadCount = 0)) then begin
     FActive:=False;
     if Assigned(FOnStopped) then
        FOnStopped(Self);
     end;
  end;

procedure TPipeServer.DoStartup;
begin
  if Assigned(PipesLogProc) then
     PipesLogProc('TPipeServer.DoStartup');
  // If we are active then exit
  if FActive then exit;

  // while (DebugHook=0) do
  // sleep(100);

  // Make sure the kill event is in a non-signaled state
  ResetEvent(FKillEv);

  {$ifdef EXTENDEDLOGGING}
  if Assigned(PipesLogProc) then PipesLogProc('TPipeServer.DoStartup '+FPipeName);
  {$endif}

  // Resource protection
  try
     // Create the listener thread
     Inc(FThreadCount);
     if Assigned(PipesLogProc) then
        PipesLogProc('TPipeServer.DoStartup, FThreadCount now '+IntToStr(FThreadCount));
     FListener:=TPipeListenThread.Create(Self, FKillEv);
     FListener.OnTerminate:=RemoveListenerThread;
  except
     // Exception during thread create. Decrement the thread count and
     // re-raise the exception
     FreeAndNil(FListener);
     Dec(FThreadCount);
     raise;
  end;

  // Set active state
  FActive:=True;
  if Assigned(PipesLogProc) then
     PipesLogProc('TPipeServer.DoStartup done '+FPipeName);
  end;

function TPipeServer.FindClientNumForPipe(const p: HPIPE): Integer;
var i:Integer;
begin
  EnterCriticalSection(FCritical);
  try
    for i:=0 to ClientCount do
       if Clients[i]=p then begin
          Result:=i;
          Exit;
          end;
    Result:=-1;
    finally
      LeaveCriticalSection(FCritical);
    end;
  end;

procedure TPipeServer.DoShutdown;
var  msg:        TMsg;
     failsafe:Int64;
begin
  if Assigned(PipesLogProc) then
     PipesLogProc('TPipeServer.DoShutdown '+FPipeName);

  if not Assigned(self) or not FActive then
     Exit;

  // Resource protection
  try
     // Set shutdown flag
     FInShutDown:=True;
     if Assigned(FListener) then
        FListener.Terminate;
     // Signal the kill event
     SetEvent(FKillEv);
     // Wait until all threads have completed (or we hit failsafe)
     failsafe:=GetTickCount64;
     while (FThreadCount > 0) do
     begin
        // Process messages (which is how the threads synchronize with our thread)
        if PeekMessage(msg, 0, 0, 0, PM_REMOVE) then
        begin
           TranslateMessage(msg);
           DispatchMessage(msg);
        end;
        if (GetTickCount64 > failsafe+1000) then
           break;
     end;
  finally
     // Set active state to false
     FInShutDown:=False;
     FActive:=False;
  end;
  {$ifdef EXTENDEDLOGGING}
  if Assigned(PipesLogProc) then PipesLogProc('TPipeServer.DoShutdown done '+FPipeName);
  {$endif}
end;

////////////////////////////////////////////////////////////////////////////////
//
//   TPipeServerThread
//
////////////////////////////////////////////////////////////////////////////////
constructor TPipeServerThread.Create(PipeServer: TPipeServer; Pipe: HPIPE; KillEvent, DataEvent: THandle);
begin
  {$ifdef EXTENDEDLOGGING}
  if Assigned(PipesLogProc) then PipesLogProc('TPipeServerThread.Create '+PipeServer.FPipeName);
  {$endif}
  // Set starting parameters
  FreeOnTerminate:=True;
  FPipe:=Pipe;
  FPipeServer:=PipeServer;
  FNotify:=PipeServer.WindowHandle;
  FErrorCode:=ERROR_SUCCESS;
  FPendingRead:=False;
  FPendingWrite:=False;
  FPipeWrite:=nil;
  FRcvSize:=MIN_BUFFER;
  FRcvBuffer:=AllocMem(FRcvSize);
  FRcvStream:=TMemoryStream.Create;
  FOlapRead.Offset:=0;
  FOlapRead.OffsetHigh:=0;
  FOlapRead.hEvent:=CreateEvent(nil, True, False, nil);
  FOlapWrite.hEvent:=CreateEvent(nil, True, False, nil);
  FEvents[0]:=KillEvent;
  FEvents[1]:=FOlapRead.hEvent;
  FEvents[2]:=FOlapWrite.hEvent;
  FEvents[3]:=DataEvent;

  // Perform inherited
  inherited Create(False{$ifdef USETGTHREADS},'PipeServerThread'{$endif});
  AddValidObject(self);
  end;

destructor TPipeServerThread.Destroy;
begin
  if not Assigned(self) or not IsValidObject(self) then
     Exit;
  {$ifdef EXTENDEDLOGGING}
  if Assigned(PipesLogProc) then PipesLogProc('TPipeServerThread.Destroy '+FPipeServer.FPipeName);
  {$endif}
  RemoveValidObject(self);
  // Free the write buffer we may be holding on to
  if FPendingWrite and Assigned(FPipeWrite) then DisposePipeWrite(FPipeWrite);

  // Free the receiver stream and buffer memory
  FreeMem(FRcvBuffer);
  FRcvStream.Free;

  // Perform inherited
  inherited Destroy;
  end;

function TPipeServerThread.QueuedRead: Boolean;
var  bRead:      Boolean;
begin

  // Set default result
  result:=True;

  // If we already have a pending read then nothing to do
  if not(FPendingRead) then
  begin
     // Set defaults for reading
     FRcvStream.Clear;
     FRcvSize:=MIN_BUFFER;
     ReAllocMem(FRcvBuffer, FRcvSize);
     // Keep reading all available data until we get a pending read or a failure
     while IsValidObject(self) and result and not(FPendingRead) do
     begin
        // Perform a read
        bRead:=ReadFile(FPipe, FRcvBuffer^, FRcvSize, FRcvRead, @FOlapRead);
        // Get the last error code
        FErrorCode:=GetLastError;
        // Check the read result
        if bRead then
        begin
           // We read a full message
           FRcvStream.Write(FRcvBuffer^, FRcvRead);
           // Call the OnData
           DoMessage;
        end
        else
        begin
           // Handle cases where message is larger than read buffer used
           if (FErrorCode = ERROR_MORE_DATA) then
           begin
              // Write the current data
              FRcvStream.Write(FRcvBuffer^, FRcvSize);
              // Determine how much we need to expand the buffer to
              if PeekNamedPipe(FPipe, nil, 0, nil, nil, @FRcvSize) then
                 ReallocMem(FRcvBuffer, FRcvSize)
              else
              begin
                 // Failure
                 FErrorCode:=GetLastError;
                 result:=False;
              end;
           end
           // Pending read
           else if (FErrorCode = ERROR_IO_PENDING) then
              // Set pending flag
              FPendingRead:=True
           else
              // Failure
              result:=False;
        end;
     end;
  end;

end;

function TPipeServerThread.CompleteRead: Boolean;
begin

  // Reset the read event and pending flag
  ResetEvent(FOlapRead.hEvent);

  // Check the overlapped results
  result:=GetOverlappedResult(FPipe, FOlapRead, FRcvRead, True);

  // Handle failure
  if not(result) then
  begin
     // Get the last error code
     FErrorCode:=GetLastError;
     // Check for more data
     if (FErrorCode = ERROR_MORE_DATA) then
     begin
        // Write the current data
        FRcvStream.Write(FRcvBuffer^, FRcvSize);
        // Determine how much we need to expand the buffer to
        result:=PeekNamedPipe(FPipe, nil, 0, nil, nil, @FRcvSize);
        if result then
        begin
           // Realloc mem to read in rest of message
           ReallocMem(FRcvBuffer, FRcvSize);
           // Read from the file again
           result:=ReadFile(FPipe, FRcvBuffer^, FRcvSize, FRcvRead, @FOlapRead);
           // Handle error
           if not(result) then
           begin
              // Set error code
              FErrorCode:=GetLastError;
              // Check for pending again, which means our state hasn't changed
              if (FErrorCode = ERROR_IO_PENDING) then
              begin
                 // Bail out and wait for this operation to complete
                 result:=True;
                 exit;
              end;
           end;
        end
        else
           // Set error code
           FErrorCode:=GetLastError;
     end;
  end;

  // Handle success
  if result then
  begin
     // We read a full message
     FRcvStream.Write(FRcvBuffer^, FRcvRead);
     // Call the OnData 
     DoMessage;
     // Reset the pending read
     FPendingRead:=False;
  end;

end;

function TPipeServerThread.QueuedWrite: Boolean;
var  bWrite:      Boolean;
begin

  // Set default result
  result:=True;

  // If we already have a pending write then nothing to do
  if not (FPendingWrite) then
  begin
     // Check state of data event
     if (WaitForSingleObject(FEvents[3], 0) = WAIT_OBJECT_0) then
     begin
        // Pull the data from the queue
        DoDequeue; // now thread safe, no more Synchronize call necessary
        // Is the record assigned?
        if Assigned(FPipeWrite) then
        begin
           // Write the data to the client
           bWrite:=WriteFile(FPipe, FPipeWrite^.Buffer^, FPipeWrite^.Count, FWrite, @FOlapWrite);
           // Get the last error code
           FErrorCode:=GetLastError;
           // Check the write operation
           if bWrite then
           begin
              {$ifdef EXTENDEDLOGGING}if Assigned(PipesLogProc) then PipesLogProc('PipeServer Wrote Data: '+IntToStr(FPipeWrite^.Count)+' bytes.');{$endif}
              // Call the OnData in the main thread
              PostMessage(FNotify, WM_PIPESEND, FPipe, FWrite);
              // Free the pipe write data
              DisposePipeWrite(FPipeWrite);
              FPipeWrite:=nil;
              // Reset the write event
              ResetEvent(FOlapWrite.hEvent);
           end
           else
           begin
              {$ifdef EXTENDEDLOGGING}
              if Assigned(PipesLogProc) then
                 PipesLogProc('PipeServer Did Not Write Data: '+
                                          IntToStr(FPipeWrite^.Count)+' bytes, err='+
                                          IntToStr(FErrorCode));{$endif}
              // Only acceptable error is pending
              if (FErrorCode = ERROR_IO_PENDING) then
                 // Set pending flag
                 FPendingWrite:=True
              else
                 // Failure
                 result:=False;
           end;
        end;
     end;
  end;

end;

function TPipeServerThread.CompleteWrite: Boolean;
begin

  // Reset the write event and pending flag
  ResetEvent(FOlapWrite.hEvent);

  // Check the overlapped results
  result:=GetOverlappedResult(FPipe, FOlapWrite, FWrite, True);

  // Handle failure
  if not(result) then
     // Get the last error code
     FErrorCode:=GetLastError
  else
     // We sent a full message so call the OnSent in the main thread
     PostMessage(FNotify, WM_PIPESEND, FPipe, FWrite);

  // We are done either way. Make sure to free the queued pipe data
  // and to reset the pending flag
  if Assigned(FPipeWrite) then
  begin
     DisposePipeWrite(FPipeWrite);
     FPipeWrite:=nil;
  end;
  FPendingWrite:=False;

end;

procedure TPipeServerThread.DoDequeue;
begin
  // Get the next queued data event
  FPipeWrite:=FPipeServer.Dequeue(FPipe);
  end;

procedure TPipeServerThread.DoMessage;
var  lpmem:      THandle;
     lpmsg:      PChar;
begin

  // Convert the memory to global memory and send to pipe server
  lpmem:=GlobalAlloc(GHND, FRcvStream.Size);
  lpmsg:=GlobalLock(lpmem);

  // Copy from the pipe
  FRcvStream.Position:=0;
  FRcvStream.Read(lpmsg^, FRcvStream.Size);

  // Unlock the memory
  GlobalUnlock(lpmem);

  // Send to the pipe server to manage
  PostMessage(FNotify, WM_PIPEMESSAGE, FPipe, lpmem);

  // Clear the read stream
  FRcvStream.Clear;

end;

procedure TPipeServerThread.Execute;
var  dwEvents:   Integer;
     bOK:        Boolean;
begin
  // Notify the pipe server of the connect
  PostMessage(FNotify, WM_PIPECONNECT, FPipe, 0);
  {$ifdef EXTENDEDLOGGING}
  if Assigned(PipesLogProc) then
     PipesLogProc('Pipe Server Thread started for pipe '+IntToStr(FPipe));
  {$endif}
  // Loop while not terminated
  while IsValidObject(self) and not(Terminated) do begin
     // Make sure we always have an outstanding read and write queued up
     bOK:=(QueuedRead and QueuedWrite);
     if bOK then begin
        // If we are in a pending write then we need will not wait for the
        // DataEvent, because we are already waiting for a write to finish
        dwEvents:=4;
        if FPendingWrite then Dec(dwEvents);
        // Handle the event that was signalled (or failure)
        case WaitForMultipleObjects(dwEvents, PWOHandleArray(@FEvents), False, INFINITE) of
           // Killed by pipe server
           WAIT_OBJECT_0     :  Terminate;
           // Read completed
           WAIT_OBJECT_0+1   :  bOK:=CompleteRead;
           // Write completed
           WAIT_OBJECT_0+2   :  bOK:=CompleteWrite;
           // Data waiting to be sent
           WAIT_OBJECT_0+3   :  ; // Data available to write
           else begin
              // General failure
              FErrorCode:=GetLastError;
              bOK:=False;
              end;
           end;
        end;

     // Check status
     if not bOK then begin
        // Call OnError in the main thread if this is not a disconnect. Disconnects
        // have their own event, and are not to be considered an error
        if (FErrorCode <> ERROR_BROKEN_PIPE) then
           PostMessage(FNotify, WM_PIPEERROR_W, FPipe, FErrorCode);
        // Terminate
        Terminate;
        end;
     end;

  {$ifdef EXTENDEDLOGGING}
  if Assigned(PipesLogProc) then
     PipesLogProc('Pipe Server Thread ending for pipe '+IntToStr(FPipe)+', error code '+IntToStr(FErrorCode));
  {$endif}

  // Disconnect and close the pipe handle at this point. This will kill the
  // overlapped events that may be attempting to access our memory blocks
  // NOTE *** Ensure that the handle is STILL valid, otherwise the ntkernel
  // will raise an exception
  if (FErrorCode <> ERROR_INVALID_HANDLE) then begin
     DisconnectNamedPipe(FPipe);
     CloseHandle(FPipe);
     end;

  // Close all open handles that we own
  CloseHandle(FOlapRead.hEvent);
  CloseHandle(FOlapWrite.hEvent);
  end;

////////////////////////////////////////////////////////////////////////////////
//
//   TPipeListenThread
//
////////////////////////////////////////////////////////////////////////////////
constructor TPipeListenThread.Create(PipeServer: TPipeServer; KillEvent: THandle);
begin
  // Set starting parameters
  FreeOnTerminate:=True;
  FPipeName:=PipeServer.PipeName;
  FPipeServer:=PipeServer;
  FNotify:=PipeServer.WindowHandle;
  FEvents[0]:=KillEvent;
  InitializeSecurity(FSA);
  FPipe:=INVALID_HANDLE_VALUE;
  FConnected:=False;
  FOlapConnect.Offset:=0;
  FOlapConnect.OffsetHigh:=0;
  FEvents[1]:=CreateEvent(@FSA, True, False, nil);;
  FOlapConnect.hEvent:=FEvents[1];

  // Perform inherited
  inherited Create(False{$ifdef USETGTHREADS},'PipeListenThread'{$endif});
  AddValidObject(self);
  end;

destructor TPipeListenThread.Destroy;
begin
  if not Assigned(self) or not IsValidObject(self) then
     Exit;
  RemoveValidObject(self);

  try
    // Close the connect event handle
    CloseHandle(FOlapConnect.hEvent);

    // Disconnect and free the handle
    if (FPipe <> INVALID_HANDLE_VALUE) then begin
       if FConnected then
          DisconnectNamedPipe(FPipe);
       CloseHandle(FPipe);
       end;

    // Release memory for security structure
    FinalizeSecurity(FSA);
    except
      // really don't know what to do here
      // exceptions are really rare here
    end;

  // Perform inherited
  inherited Destroy;
  end;

function TPipeListenThread.CreateServerPipe(const reopening:Boolean): Boolean;
const
  PipeMode       =  PIPE_TYPE_MESSAGE or PIPE_READMODE_MESSAGE or PIPE_WAIT;
  Instances      =  PIPE_UNLIMITED_INSTANCES;
  FILE_FLAG_FIRST_PIPE_INSTANCE = $00080000;
var OpenMode:Integer;
begin
  OpenMode := PIPE_ACCESS_DUPLEX or FILE_FLAG_OVERLAPPED;

  if not reopening and FPipeServer.FMustBeFirstInstance then
     OpenMode:=OpenMode or FILE_FLAG_FIRST_PIPE_INSTANCE;

  // Create the outbound pipe first
  FullPipeName:='\\.\pipe\'+FPipeName;
  FPipe:=CreateNamedPipe(PChar(string(FullPipeName)),
                        OpenMode, PipeMode, Instances, 0, 0, 1000, @FSA);

  // Set result value based on valid handle
  if (FPipe = INVALID_HANDLE_VALUE) then
     FErrorCode:=GetLastError
  else
     FErrorCode:=ERROR_SUCCESS;

  // Success if handle is valid
  result:=(FPipe <> INVALID_HANDLE_VALUE);
  end;

procedure TPipeListenThread.DoWorker;
begin
  // Call the pipe server on the main thread to add a new worker thread
  FPipeServer.AddWorkerThread(FPipe);
  end;

procedure TPipeListenThread.Execute;
var firsttime:Boolean;
    WFMO:DWORD;
begin
  // Thread body
  firsttime:=true;
  if Assigned(PipesLogProc) then
     PipesLogProc('TPipeListenThread.Execute '+FPipeName);
  while IsValidObject(self) and not (Terminated) do begin
     // Set default state
     FConnected:=False;
     // Attempt to create first pipe server instance
     if CreateServerPipe(not firsttime) then begin
        if Assigned(PipesLogProc) then
           if firsttime then
              PipesLogProc('Server Pipe Created')
           else
              PipesLogProc('Server Pipe Reopened');

        firsttime:=false;
        // Connect the named pipe
        FConnected:=ConnectNamedPipe(FPipe, @FOlapConnect);
        // Handle failure
        if not(FConnected) then begin
           // Check the last error code
           FErrorCode:=GetLastError;
           if Assigned(PipesLogProc) then
              PipesLogProc('Not Connected Yet, Code '+IntToStr(FErrorCode));

           // Is pipe connected?
           if (FErrorCode = ERROR_PIPE_CONNECTED) then
              FConnected:=True
           // IO pending?
           else if(FErrorCode = ERROR_IO_PENDING) then begin
              // Wait for a connect or kill signal
              WFMO:=WaitForMultipleObjects(2, PWOHandleArray(@FEvents), False, INFINITE);
              if Assigned(PipesLogProc) then
                 PipesLogProc('WaitForMultipleObjects Result: '+IntToStr(WFMO));
              case WFMO of
                 WAIT_FAILED       : begin
                     FErrorCode:=GetLastError;
                     if Assigned(PipesLogProc) then
                        PipesLogProc('TPipeListenThread.Execute Failed - Code: '+IntToStr(FErrorCode));
                     end;
                 WAIT_OBJECT_0     :  begin
                     if Assigned(PipesLogProc) then
                        PipesLogProc('TPipeListenThread.Execute Terminating');
                     Terminate;
                     end;
                 WAIT_OBJECT_0+1   :  begin
                     FConnected:=True;
                     if Assigned(PipesLogProc) then
                        PipesLogProc('TPipeListenThread.Execute Succeeded');
                     end;
                 end;
              end;
           end;
        // If we are not connected at this point then we had a failure
        if not (FConnected) then begin
           if Assigned(PipesLogProc) then
              PipesLogProc('TPipeListenThread.Execute Not Connected');
           // Client may have connected / disconnected simultaneously, in which
           // case it is not an error. Otherwise, post the error message to the
           // pipe server
           if (FErrorCode <> ERROR_NO_DATA) then
              PostMessage(FNotify, WM_PIPEERROR_L, FPipe, FErrorCode);
           // Close the handle
           CloseHandle(FPipe);
           FPipe:=INVALID_HANDLE_VALUE;
           end
        else begin
           if Assigned(PipesLogProc) then
              PipesLogProc('TPipeListenThread.Execute Calling SafeSynchronize(DoWorker)');
           // Notify server of connect
           SafeSynchronize(DoWorker);
           end;
        end
     else begin
        //FPipeServer.Active:=false; this causes problems
        if Assigned(PipesLogProc) then
           PipesLogProc('TPipeListenThread.Execute breaking');
        break;
        end;
  if Assigned(PipesLogProc) then
     PipesLogProc('TPipeListenThread.Execute looping.');
  end;

  if Assigned(PipesLogProc) then
     PipesLogProc('TPipeListenThread.Execute end.');
end;

////////////////////////////////////////////////////////////////////////////////
//
//   TPipeThread
//
////////////////////////////////////////////////////////////////////////////////
procedure TPipeThread.SafeSynchronize(Method: TThreadMethod);
begin
  // Exception trap
  try
     // Call
     Synchronize(Method);
  except
     // Trap and eat the exception, just call terminate on the thread
     Terminate;
  end;

end;

////////////////////////////////////////////////////////////////////////////////
//
//   TWriteQueue
//
////////////////////////////////////////////////////////////////////////////////
constructor TWriteQueue.Create;
begin
  // Perform inherited
  inherited Create;

  InitializeCriticalSection(FCritical);

  // Starting values
  FHead:=nil;
  FTail:=nil;
  FDataEv:=CreateEvent(nil, True, False, nil);
  AddValidObject(self);
  end;

destructor TWriteQueue.Destroy;
begin
  if not Assigned(self) or not IsValidObject(self) then
     Exit;
  RemoveValidObject(self);
  // Clear
  Clear;

  // Close the data event handle
  CloseHandle(FDataEv);

  DeleteCriticalSection(FCritical);

  // Perform inherited
  inherited Destroy;
  end;

procedure TWriteQueue.Clear;
var  node:       PWriteNode;
begin
  EnterCriticalSection(FCritical);

  try
    // Reset the writer event
    ResetEvent(FDataEv);
    // Free all the items in the stack
    while Assigned(FHead) do begin
       // Get the head node and push forward
       node:=FHead;
       FHead:=FHead^.NextNode;
       // Free the pipe write data
       DisposePipeWrite(node^.PipeWrite);
       // Free the queued node
       FreeMem(node);
       end;

    // Set the tail to nil
    FTail:=nil;

    // Reset the count
    finally
      LeaveCriticalSection(FCritical);
    end;
  end;

function TWriteQueue.NewNode(PipeWrite: PPipeWrite): PWriteNode;
begin
  // Allocate memory for new node
  result:=AllocMem(SizeOf(TWriteNode));

  // Set the structure fields
  result^.PipeWrite:=PipeWrite;
  result^.NextNode:=nil;
  end;

procedure TWriteQueue.Enqueue(PipeWrite: PPipeWrite);
var  node:PWriteNode;
begin
  // Create a new node
  node:=NewNode(PipeWrite);

  EnterCriticalSection(FCritical);
  try
    // Make this the last item in the queue
    if (FTail = nil) then
       FHead:=node
    else
       FTail^.NextNode:=node;

    // Update the new tail
    FTail:=node;

    // Set the write event to signalled
    SetEvent(FDataEv);
    finally
      LeaveCriticalSection(FCritical);
    end;
  end;

function TWriteQueue.GetCount: Integer;
var p:PWriteNode;
begin
  Result:=0;

  EnterCriticalSection(FCritical);
  try
    p:=FHead;
    while Assigned(p) do begin
      Inc(Result);
      p:=p^.NextNode;
      end;
    finally
      LeaveCriticalSection(FCritical);
    end;
  end;

function TWriteQueue.Dequeue: PPipeWrite;
var  node:       PWriteNode;
begin
  Result:=nil;
  if not IsValidObject(self) then
     Exit;
  EnterCriticalSection(FCritical);
  try
    // Remove the first item from the queue
    if not Assigned(FHead) then
       result:=nil
    else begin
       // Set the return data
       result:=FHead^.PipeWrite;
       // Move to next node, update head (possibly tail), then free node
       node:=FHead;
       if (FHead = FTail) then
          FTail:=nil;
       FHead:=FHead^.NextNode;
       // Free the memory for the node
       FreeMem(node);
       end;

    // Reset the write event if no more data records to write
    if GetCount = 0 then
       ResetEvent(FDataEv);
    finally
      LeaveCriticalSection(FCritical);
    end;
  end;

////////////////////////////////////////////////////////////////////////////////
//
//   Utility functions
//
////////////////////////////////////////////////////////////////////////////////
function AllocPipeWrite(const Buffer; Count: Integer): PPipeWrite;
begin

  // Allocate memory for the result
  result:=AllocMem(SizeOf(TPipeWrite));

  // Set the count of the buffer
  result^.Count:=Count;

  // Allocate enough memory to store the data buffer, then copy the data over
  result^.Buffer:=AllocMem(Count);
  System.Move(Buffer, result^.Buffer^, Count);

end;

procedure DisposePipeWrite(PipeWrite: PPipeWrite);
begin
  if Assigned(PipeWrite) then begin
     // Dispose of the memory being used by the pipe write structure
     if Assigned(PipeWrite^.Buffer) then FreeMem(PipeWrite^.Buffer);
     // Free the memory record
     FreeMem(PipeWrite);
     end;
  end;

procedure CheckPipeName(Value: String);
begin
  // Validate the pipe name
  if (Pos('\', Value) > 0) or
     (Length(Value) > 63) or
     (Length(Value) = 0) then
  begin
     raise EPipeException.CreateRes(PResStringRec(@resBadPipeName));
  end;

end;

procedure InitializeSecurity(var SA: TSecurityAttributes);
var  sd:         PSecurityDescriptor;
begin

  // Allocate memory for the security descriptor
  sd:=AllocMem(SECURITY_DESCRIPTOR_MIN_LENGTH);

  // Initialise the new security descriptor
  InitializeSecurityDescriptor(sd, SECURITY_DESCRIPTOR_REVISION);

  // Add a NULL descriptor ACL to the security descriptor
  SetSecurityDescriptorDacl(sd, True, nil, False);

  // Set up the security attributes structure
  with SA do
  begin
     nLength:=SizeOf(TSecurityAttributes) ;
     lpSecurityDescriptor:=sd;
     bInheritHandle:=True;
  end;

end;

procedure FinalizeSecurity(var SA: TSecurityAttributes);
begin

  // Release memory that was assigned to security descriptor
  if Assigned(SA.lpSecurityDescriptor) then
  begin
     FreeMem(SA.lpSecurityDescriptor);
     SA.lpSecurityDescriptor:=nil;
  end;

end;

function TPipeClient.Busy:Boolean;
begin
  Busy:=(FWriteQueue.GetCount>0) or
        Assigned(FWorker) and not FWorker.Terminated;
  end;

initialization
  isMainThread:=true;
  InitValidObjects;

finalization
  FinalizeValidObjects;

{$endif}

end.


