object FNamedPipesTester: TFNamedPipesTester
  Left = 0
  Top = 0
  Margins.Left = 6
  Margins.Top = 6
  Margins.Right = 6
  Margins.Bottom = 6
  Caption = 'Named Pipes Tester'
  ClientHeight = 1053
  ClientWidth = 1254
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -24
  Font.Name = 'Segoe UI'
  Font.Style = []
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  PixelsPerInch = 192
  TextHeight = 32
  object memServer: TMemo
    Left = 11
    Top = 208
    Width = 614
    Height = 529
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    Lines.Strings = (
      'Pipe Server Messages:')
    TabOrder = 0
  end
  object memClient: TMemo
    Left = 659
    Top = 208
    Width = 481
    Height = 529
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    Lines.Strings = (
      'Pipe Client Messages:')
    TabOrder = 1
  end
  object btStartServer: TButton
    Left = 16
    Top = 48
    Width = 337
    Height = 41
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    Caption = 'Start Pipe Server'
    TabOrder = 2
    OnClick = btStartServerClick
  end
  object btStopServer: TButton
    Left = 16
    Top = 101
    Width = 337
    Height = 41
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    Caption = 'Stop Pipe Server'
    TabOrder = 3
    OnClick = btStopServerClick
  end
  object btConnect: TButton
    Left = 659
    Top = 48
    Width = 246
    Height = 41
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    Caption = 'Connect to Server'
    TabOrder = 4
    OnClick = btConnectClick
  end
  object btSendMsgToServer: TButton
    Left = 659
    Top = 154
    Width = 246
    Height = 41
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    Caption = 'Send Msg to Server'
    TabOrder = 5
    OnClick = btSendMsgToServerClick
  end
  object btDisconnect: TButton
    Left = 659
    Top = 101
    Width = 246
    Height = 41
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    Caption = 'Disconnect'
    TabOrder = 6
    OnClick = btDisconnectClick
  end
  object btSendMsgToClient: TButton
    Left = 16
    Top = 154
    Width = 337
    Height = 41
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    Caption = 'Broadcast Msg to Clients'
    TabOrder = 7
    OnClick = btSendMsgToClientClick
  end
  object memGeneralLog: TMemo
    Left = 11
    Top = 784
    Width = 1129
    Height = 258
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    Lines.Strings = (
      'General Debug Log:')
    TabOrder = 8
  end
end
