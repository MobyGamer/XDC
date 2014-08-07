unit xdc_log;
{provides debug logging.  Currently writes to a file, but could later
be expanded to have a special debug window or something.}

interface

const
  Logging:boolean=false;

procedure openLogging(s:string);
procedure stdout(s:string);
procedure logAtomic(s:string);
procedure stderr(s:string);
procedure closeLogging;

implementation

uses
  xdc_globals;

var
  logout:text;

procedure openLogging(s:string);
begin
  assign(logout,s);
  rewrite(logout);
  Logging:=true;
end;

procedure logAtomic(s:string);
var
  f:text;
begin
  assign(f,'atomic.log');
  rewrite(f);
  writeln(f,s);
  close(f);
end;

procedure stdout(s:string);
begin
  if logging and (debug<>0) then writeln(logout,s);
  {logatomic(s);}
end;

procedure stderr(s:string);
begin
  if logging and (debug<>0) then writeln(logout,'*** '+s);
end;

procedure closeLogging;
begin
  if logging then close(logout);
  Logging:=false;
end;

end.