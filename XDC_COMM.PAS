unit xdc_common;
{procedures and functions common to both the encoder and player}

interface

procedure xdc_setvid(b:byte); {set video mode}
procedure fatalerr(s:string);

implementation

uses
  xdc_globals,xdc_log,m6845ctl;

procedure xdc_setvid(b:byte);
{1=160x200x16, 2=640x200x2, 3=160x200x16 Tandy/PCjr, 4=240x128x2 HP 95LX}
begin
  case b of
    1:asm
      mov ax,0006
      int 10h
      {turn on colorburst}
      mov dx,m6845_mode_ctl
      mov al,c_videosignal_enable+c_graphics_enable+c_640x200_enable
      out dx,al
    end;
    2:asm
      mov ax,0006
      int 10h
    end;
    3:asm
      mov ax,0008
      int 10h
    end;
{$IFDEF HP95LX}
    4:asm
      mov ax,0020h
      int 10h
    end;
{$ENDIF}
  end;
end;

procedure fatalerr(s:string);
begin
  s:='FATAL ERROR: '+s;
  if logging then stderr(s);
  {doneCompiler;}
  asm
    mov ax,0003
    int 10h
  end;
  writeln(s);
  halt(1);
end;

end.
