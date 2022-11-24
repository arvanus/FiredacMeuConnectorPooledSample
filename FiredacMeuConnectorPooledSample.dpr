program FiredacMeuConnectorPooledSample;

{$APPTYPE CONSOLE}
{$R *.res}

uses
  System.SysUtils,
  Threading,
  Classes,
  Horse,
  MeuConectorBD in 'src\MeuConectorBD.pas';

begin
  try
    { TODO -oUser -cConsole Main : Insert code here }
    var
    t1 := TThread.GetTickCount64;
    for var i := 0 to 100 do
    begin
      var
      lCon := TMinhaConexao.DescreverConexao('localhost', 'employee', 'NONE',
        'SYSDBA', 'masterkey', '');
      var
      lQuery := TMinhaQuery.Create(lCon, true);
      try
        lCon.Connect;
        try
          lQuery.sql.add('select current_connection as con from rdb$database');
          lQuery.open;
          writeln(lQuery.fieldbyname('con').asString);
        finally
          lQuery.free;
        end;
        lCon.DisconnectToPool; // lCon.Disconnect is similar in this case;
      finally
        lCon.free;
      end;
    end;

    var
    t2 := TThread.GetTickCount64;
    for var i := 0 to 100 do
    begin
      var
      lCon := TMinhaConexao.DescreverConexao('localhost', 'employee', 'NONE',
        'SYSDBA', 'masterkey', '', false);
      var
      lQuery := TMinhaQuery.Create(lCon, true);
      try
        lCon.Connect;
        try
          lQuery.sql.add('select current_connection as con from rdb$database');
          lQuery.open;
          writeln(lQuery.fieldbyname('con').asString);
        finally
          lQuery.free;
        end;
        lCon.disconnect;
      finally
        lCon.free;
      end;
    end;

    writeln('Tempo pool: ' + (t2 - t1).toString + 'ms');
    writeln('  sem pool: ' + (TThread.GetTickCount64 - t2).toString + 'ms');

    Thorse.all('/pool',
      procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
      begin
        var
        lCon := TMinhaConexao.DescreverConexao('localhost', 'employee', 'NONE',
          'SYSDBA', 'masterkey', '');
        var
        lQuery := TMinhaQuery.Create(lCon, true);
        try
          lCon.Connect;
          try
            lQuery.sql.add
              ('select current_connection as con from rdb$database');
            lQuery.open;
            Res.Send('ID da conexão ao banco: ' + lQuery.fieldbyname('con')
              .asString);
          finally
            lQuery.free;
          end;
          lCon.DisconnectToPool; // lCon.Disconnect is similar in this case;
        finally
          lCon.free;
        end;

      end);

    Thorse.all('/direto',
      procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
      begin
        var
        lCon := TMinhaConexao.DescreverConexao('localhost', 'employee', 'NONE',
          'SYSDBA', 'masterkey', '', false);
        var
        lQuery := TMinhaQuery.Create(lCon, true);
        try
          lCon.Connect;
          try
            lQuery.sql.add
              ('select current_connection as con from rdb$database');
            lQuery.open;
            Res.Send('ID da conexão ao banco: ' + lQuery.fieldbyname('con')
              .asString);
          finally
            lQuery.free;
          end;
          lCon.DisconnectToPool; // lCon.Disconnect is similar in this case;
        finally
          lCon.free;
        end;

      end);

    Thorse.listen(9000);

  except
    on E: Exception do
      writeln(E.ClassName, ': ', E.Message);
  end;

end.
