unit MeuConectorBD;

interface

uses FireDAC.Phys,
  Data.DB,
  FireDAC.Comp.Client,
  FireDAC.Phys.FB,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.DApt,
  FireDAC.ConsoleUI.Wait,
  FireDAC.Stan.Option,
  classes, sysutils;

type

  TMinhaSessao = class(TFDManager)
    // não uso pra nada além do controle interno do pool
  public
    constructor Create(AOwner: TComponent); override;
  end;

  TMinhaConexao = class(Tfdconnection)
  private
  public
    constructor DescreverConexao(pServer: String; pDataBase: String;
      pCharSet: String; pUser, pPassword, pRole: String;
      pUsarPool: boolean = true); overload; virtual;
    procedure Connect;
    procedure Disconnect;
    // Seria interessante diferenciar ambos os métodos, forçando o disconnect a não enviar para o pool
    procedure DisconnectToPool;
    destructor Destroy; override;
  end;

  TMinhaTransacao = class(TFDTransaction)
    // Se voce não entendeu buflufas do por que escolhi esses constructores padrão então leia aqui:
    // https://ib-aid.com/en/transactions-in-firebird-acid-isolation-levels-deadlocks-and-update-conflicts-resolution/
    constructor Create(pbanco: TMinhaConexao); virtual;
    constructor createNoWait(pbanco: TMinhaConexao); virtual;
    constructor CreateReadOnly(pbanco: TMinhaConexao); virtual;
    constructor CreateReadOnlySnapshot(pbanco: TMinhaConexao); virtual;
    destructor Destroy; virtual;
    function inTransaction: boolean;
    procedure Commit; virtual;
    procedure CommitRetaining; virtual;
    procedure Rollback; virtual;
    procedure RollbackRetaining; virtual;
  end;

  TMinhaQuery = class(TFDQuery)
  private
    fTransaction: TMinhaTransacao;
    AutoFreeTransaction: boolean;
    function getDatabase: TMinhaConexao;
    function getTransaction: TMinhaTransacao;
  protected
    { Protected declarations }
  public
    { Public declarations }
    property Database: TMinhaConexao read getDatabase;
    property Transaction: TMinhaTransacao read getTransaction;
    //
    procedure Commit; virtual;
    procedure Rollback; virtual;
    //
    constructor Create(pbanco: TMinhaConexao; pTransacao: TMinhaTransacao);
      overload; virtual;
    constructor Create(pbanco: TMinhaConexao; pReadOnly: boolean = false);
      overload; virtual;
    destructor Destroy; override;

  end;

var
  mySession: TMinhaSessao;
  FDPhysFBDriverLink1: TFDPhysFBDriverLink;
  // Nota: voce ainda precisaria criar os drivers de acesso do Firedac

implementation

{ TMinhaConexao }

procedure TMinhaConexao.Connect;
begin
  self.Connected := true;
end;

destructor TMinhaConexao.Destroy;
begin

  inherited;
end;

procedure TMinhaConexao.Disconnect;
begin
  self.Connected := true;
end;

procedure TMinhaConexao.DisconnectToPool;
begin
  self.Connected := false;
end;

constructor TMinhaConexao.DescreverConexao(pServer: String; pDataBase: String;
  pCharSet: String; pUser, pPassword, pRole: String; pUsarPool: boolean);
var
  lParams: TStrings;
  lConDef: String;
begin

  inherited Create(nil);
  self.Connected := false;
  self.TxOptions.Isolation := xiReadCommitted;

  lParams := TStringList.Create;
  try
    lParams.Clear;
    lParams.Values['Database'] := pDataBase;
    lParams.Values['User_Name'] := pUser;
    lParams.Values['Password'] := pPassword;
    lParams.Values['RoleName'] := pRole;
    lParams.Values['Protocol'] := 'TCPIP';
    lParams.Values['Server'] := pServer;
    if pCharSet.Trim.IsEmpty then
      lParams.Values['CharacterSet'] := 'ISO8859_1'
    else
      lParams.Values['CharacterSet'] := pCharSet;
    lParams.Values['DriverID'] := 'FB';
    // Ajustar para outros métodos, não ví sentido em por isso no contructor por ser muito "Firedac dependent"
    lParams.Values['Pooled'] := 'true';
    lConDef := lParams.Text.Replace(sLineBreak, '_', [rfReplaceAll])
      .Replace(' ', '_', [rfReplaceAll]);
    if pUsarPool then
    begin
      if not mySession.IsConnectionDef(lConDef) then
        mySession.AddConnectionDef(lConDef, lParams.Values['DriverID'],
          lParams, true);

      self.ConnectionDefName := lConDef;
    end
    else
    begin
      self.Params.Assign(lParams);
      self.Params.Values['Pooled'] := 'false';

    end;
  finally
    lParams.Free;
  end;
end;

{ TMinhaQuery }

constructor TMinhaQuery.Create(pbanco: TMinhaConexao;
  pTransacao: TMinhaTransacao);
begin
  inherited Create(pbanco);
  self.Connection := pbanco;
  self.AutoFreeTransaction := pTransacao = nil;
  inherited Transaction := pTransacao;
  if self.AutoFreeTransaction then
  begin
    inherited Transaction := TMinhaTransacao.Create(pbanco);
  end;
  self.fTransaction := inherited Transaction as TMinhaTransacao;
end;

procedure TMinhaQuery.Commit;
begin
  if not self.AutoFreeTransaction then
    raise Exception.Create
      ('Transação não é própria, realize o controle direto nela!');
  self.Transaction.Commit;
end;

constructor TMinhaQuery.Create(pbanco: TMinhaConexao; pReadOnly: boolean);
begin
  inherited Create(pbanco);
  self.Connection := pbanco;
  self.AutoFreeTransaction := true;
  inherited Transaction := TMinhaTransacao.Create(pbanco);
  self.fTransaction := inherited Transaction as TMinhaTransacao;
  self.Transaction.Options.ReadOnly := pReadOnly;

end;

destructor TMinhaQuery.Destroy;
begin
  if AutoFreeTransaction then
  begin
    try
      if Transaction.Active then
        Transaction.Commit;
    except

    end;
    Transaction.Free;
  end;
  inherited;
end;

function TMinhaQuery.getDatabase: TMinhaConexao;
begin
  result := inherited Connection as TMinhaConexao;
end;

function TMinhaQuery.getTransaction: TMinhaTransacao;
begin
  result := fTransaction;
end;

procedure TMinhaQuery.Rollback;
begin
  if not self.AutoFreeTransaction then
    raise Exception.Create
      ('Transação não é própria, realize o controle direto nela!');
  self.Transaction.Rollback;
end;

{ TMinhaTransacao }

procedure TMinhaTransacao.Commit;
begin
  if not self.Active then
    exit;
  inherited;
end;

procedure TMinhaTransacao.CommitRetaining;
begin
  if not self.Active then
    exit;
  inherited;
end;

constructor TMinhaTransacao.Create(pbanco: TMinhaConexao);
begin
  inherited Create(pbanco);
  self.Connection := pbanco;

  self.Options.Isolation := TFDTxIsolation.xiReadCommitted;
  self.Options.ReadOnly := false;
  self.Options.AutoCommit := false;
  self.Options.AutoStart := true;
  self.Options.AutoStop := false;
  self.Options.StopOptions := [];
  // self.Options.StopOptions - [xoIfCmdsInactive];
  self.Options.Params.Add('wait');
  self.Options.Params.Add('lock_timeout=120'); // 120 segundos p/ timeout
end;

constructor TMinhaTransacao.createNoWait(pbanco: TMinhaConexao);
begin
  inherited Create(pbanco);
  self.Connection := pbanco;

  self.Options.Isolation := TFDTxIsolation.xiReadCommitted;
  self.Options.ReadOnly := false;
  self.Options.AutoCommit := false;
  self.Options.AutoStart := true;
  self.Options.AutoStop := false;
  self.Options.StopOptions := [];
  // self.Options.StopOptions - [xoIfCmdsInactive];
  self.Options.Params.Add('nowait');

end;

constructor TMinhaTransacao.CreateReadOnly(pbanco: TMinhaConexao);
begin
  inherited Create(pbanco);
  self.Connection := pbanco;

  self.Options.Isolation := TFDTxIsolation.xiReadCommitted;
  self.Options.ReadOnly := true;
  self.Options.AutoCommit := false;
  self.Options.AutoStart := true;
  self.Options.AutoStop := false;
  self.Options.StopOptions := [];
  // self.Options.StopOptions - [xoIfCmdsInactive];
  self.Options.Params.Add('nowait'); // na verdade não importa no read-only
end;

constructor TMinhaTransacao.CreateReadOnlySnapshot(pbanco: TMinhaConexao);
begin
  inherited Create(pbanco);
  self.Connection := pbanco;

  self.Options.Isolation := TFDTxIsolation.xiSnapshot;
  // Ideal para casos onde serão lidas várias queries e voce quer manter a consistencia dos dados desde o início da transação
  self.Options.ReadOnly := true;
  self.Options.AutoCommit := false;
  self.Options.AutoStart := true;
  self.Options.AutoStop := false;
  self.Options.StopOptions := [];
  // self.Options.StopOptions - [xoIfCmdsInactive];
  self.Options.Params.Add('nowait'); // na verdade não importa no read-only

end;

destructor TMinhaTransacao.Destroy;
begin
  if Active then
    raise Exception.Create('Transação não finalizada aqui, favor tratar dev!');
  // O ideal é não dar erro aqui, mas a questão é ser didática também
  inherited;
end;

function TMinhaTransacao.inTransaction: boolean;
begin
  result := self.Active;
end;

procedure TMinhaTransacao.Rollback;
begin
  if not self.Active then
    exit;
  inherited;

end;

procedure TMinhaTransacao.RollbackRetaining;
begin
  if not self.Active then
    exit;
  inherited;

end;

{ TMinhaSessao }

constructor TMinhaSessao.Create(AOwner: TComponent);
begin
  inherited;

end;

initialization

mySession := TMinhaSessao.Create(nil);
FDPhysFBDriverLink1 := TFDPhysFBDriverLink.Create(nil);

finalization

FreeAndNil(mySession);
FreeAndNil(FDPhysFBDriverLink1);

end.
