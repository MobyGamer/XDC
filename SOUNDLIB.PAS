{$IFNDEF VER60}
{$A+,B+,F-,G-,I-,O+,P+,Q-,R-,S-,T-,V-,X+,Y-}
{$ELSE}
{ Uh.... not enough money for BP7? }
{$A+,B+,F-,G-,I-,O+,R-,S-,V-,X+}
{$ENDIF}
(****************************************************************************
 * Author           : Stefan Goehler, Germany                               *
 * Version          : 1.2c                                                  *
 * Task             : Play and record with soundblaster and compatibles     *
 * You can use my units entirely in your own programs. Ripping any code off *
 * is not allowed without my permission. If you wanna use this unit in      *
 * commercial products, I mean if you wanna get ANY money or other for      *
 * software based on one of my units, you'll have to contact me - we'll     *
 * find a way.                                                              *
 *******                                                                    *
 * If there are any bugs, please email me!                                  *
 * If you don't know where the bug is, tell me what happened and also give  *
 * me your machine configuration. BTW, I am not responsible for any problems*
 * with non- Creative soundcards! Even if there is written, the card is 100%*
 * SB-compatible. If you have a problem on a non-SB, then you see that it   *
 * is not 100% compatible! Please don't bother me with such things then!    *
 *                                                                          *
 * my homepage: http://www.crossfire-designs.de                             *
 * ^^^note that you can get there always the actual version of this unit    *
 * if you have additions, tips or sth. else, mail to stefan.goehler@gmx.de  *
 ****** KNOWN PROBLEMS ******************************************************
 * . The program is not able to play any compressed files.                  *
 * . Soundlib will only play the first chunk of multi-chunked files         *
 ****** HISTORY *************************************************************
 * History                                                                  *
 * Version 1.0 : .first public available Version                            *
 *                (4th Sep. 1997)                                           *
 * Version 1.01: *fixed a bug with multifiles- LASTONE wasn't setted back   *
 *                and the sb played not without reseta 16bit-file after a   *
 *                8bit file correctly                                       *
 *               +added some additional in the readme                       *
 *                (6th Sep. 1997)                                           *
 * Version 1.1   -removed needless things                                   *
 *               +added surround sound                                      *
 *               *fixed a bug when playback runs, that you can't open a file*
 *               +added function getactpos- gives back the fileremain minus *
 *                the already played sounddata - very accurate              *
 *               -removed LASTONE and used a better method                  *
 *               *fixed bug that the file won't play to the full end        *
 *                (9th Sep. 1997)                                           *
 * Version 1.11  *fixed a bug which won't set the speaker on with older     *
 *                version of soundblasters                                  *
 *               *soundlib is now runable under TP6 without any changes     *
 * Version 1.12  *changed 'pitch' to 'treble'                               *
 *               *fixed a little bug that causes terrible sounds with some  *
 *                files smaller than the doublebuffer                       *
 *               *changed line to linein because of conflicts with linedraw *
 * Version 1.13  *changed wave-loader in that way it can also read wav-files*
 *                with additional chunks (like program, copyright...etc)    *
 *                (31st March 1998)                                         *
 * Version 1.14  +new procedure getblasterstring - get name of the SB       *
 *               *procedure errorproc is a variable - so if you have a gui  *
 *                you are able to make a workaround for the textmode        *
 *                error-messages                                            *
 *               *voc-loader should now load nearly all vocs                *
 *               +Protected mode support                                    *
 *               *improved error-checking in procedure initblaster          *
 *               *downsample-handling improved                              *
 *               *removed some detail bugs                                  *
 *                (18th July 1998)                                          *
 * Version 1.15  +SB Pro 2.0 support added                                  *
 *               *fixed small bug in dmagetpos                              *
 *               +made setagc public (why did I forget that???)             *
 *               *fixed bug that the player doesn't play the last block     *
 *                (9th November 1998)                                       *
 * Version 1.2   *fixed bug which caused nasty clicking, if wave file       *
 *                contained additional data at the end                      *
 *               *fixed problem concerning the SBLive! SB16 emulator, which *
 *                caused the detection routine to say the soundcard is busy *
 *               *far better sounding stereo to mono downsampling           *
 *               *SB Live! detection included (I hope only this one has     *
 *                DSP version $40D), plus its support for 48 Khz            *
 * Version 1.2a  *fixed playback problems under W2k sound emulators         *
 * Version 1.2b  *8088 fixes, interrupt speedups by Trixter                 *
 * Version 1.2c  *Investigated early return from interrupts                 *
 * Version 1.2d  *String and other size optimizations                       *
 ****** FUTURE EXTENSIONS ***************************************************
 * .ADPCM decoder                                                           *
 * .variable samplerate converter                                           *
 ****************************************************************************)
{Bugs:
 - Probleme bei kleinen Files und downsampling
 - bei downsamping mit SBpro ab 2. Block nur halbe samplingrate}

{$G-}

{{$DEFINE REENTRANT}
{
Define this if you need interrupts enabled while inside the interrupt
handler.  This would be the case if your user-land interrupt handler code
(callproc) takes too long and/or you're on a slow 808x machine.  Generally,
don't enable this unless you know what you're doing.
}

{{$DEFINE LONGINTR}
{
If defined, it is assumed that the interrupt handler will take longer
than normal.  This flag will enable interrupts as soon as possible so
as to not bork other interrupts on the system.  However, this means it
is remotely possible that we will get called before we're done running;
in that case, we need to enable the re-entrancy code, shown below:
}

{$IFDEF LONGINTR}
  {$DEFINE REENTRANT}
{$ENDIF}

UNIT soundlib;
INTERFACE
USES
{$IFNDEF DPMI}
dos;
{$ELSE}
dos, winapi;
{$ENDIF}

TYPE
  {$IFDEF DPMI}
  tmemp = LONGINT;
  {$ELSE}
  tmemp = POINTER;
  {$ENDIF}
  tplay = RECORD
            hispeed    : BOOLEAN;{ SbPro internal usage }

            blocksize  : LONGINT;{ half size of the getted buffermemory            }
            p          : tmemp;  { pointer to the sounddata buffermemory           }
            activeblock : BYTE;   { active bufferblock (because of doublebuffering) }
            callproc   : PROCEDURE;{ the procedure to call with the interrupt      }

            stopped    : BOOLEAN;  { the playback is stopped     }
            paused     : BOOLEAN;  { playback is paused          }

            data : ARRAY [0..19] OF
            RECORD
              frequency  : LONGINT;{ samplingrate                }
              stereo     : BOOLEAN;{ file is stereo              }
              sound16bit : BOOLEAN;{ file has 16 bit data        }

              format     : WORD;   { see format constants        }
              blockalign : WORD;   { How we can seek in the file }
              signed     : BOOLEAN;{ sounddata is signed         }

              fileremain : LONGINT;{ remain of the file to play                 }
              fdatasize  : LONGINT;{ size of the real data in the file          }
              fsize      : LONGINT;{ size of the file to play                   }
              fdatastart : LONGINT;{ startposition of the sounddata in the file }
              f          : FILE;   { file to read/write                         }
              fclosed    : BOOLEAN;{ shows if the file is open or not           }
            END;
          END;

  trec = RECORD
           hispeed    : BOOLEAN; { SbPro internal usage }

           blocksize   : LONGINT;{ half size of the getted buffermemory       }
           p           : tmemp;  { pointer to the sounddata buffermemory      }
           activeblock : BYTE;   { active bufferblock (doublebuffering)       }
           callproc    : PROCEDURE;{the procedure to call with the interrupt  }

           stopped     : BOOLEAN;{ the recording is stopped                   }
           paused      : BOOLEAN;{ recording is paused                        }

           frequency   : LONGINT;{ samplingrate                               }
           stereo      : BOOLEAN;{ is recorded in stereo                      }
           sound16bit  : BOOLEAN;{ is recorded in 16 bit                      }
           format      : WORD;   { see format constants                       }
           signed      : BOOLEAN;{ is sounddata signed                        }

           fileremain  : LONGINT;{ remain of the file to play                 }
           fdatasize   : LONGINT;
           fsize       : LONGINT;{ size of the file to play                   }
           fdatastart  : LONGINT;{ startposition of the sounddata in the file }
           f           : FILE;   { file to read/write                         }
           fclosed     : BOOLEAN;{ shows if the file is open or not           }
         END;

CONST
  sblive             = $40D;
  sb16               = $400;
  sbpro20            = $301;
  sbpro              = $300;
  sb21               = $210;
  sb20               = $200;
  actfile            : BYTE = 0;{ the momently used file }

  { Constants for the dma-port-addresses }
  dma_lpage          : ARRAY [0..7] OF
  BYTE = ($87, $83, $81, $82, $88, $8B, $89, $8A);
  dma_hpage          : ARRAY [0..7] OF
  WORD = ($487, $483, $481, $482, $00, $48B, $489, $48A);
  dma_adr            : ARRAY [0..7] OF
  BYTE = ($00, $02, $04, $06, $C0, $C4, $C8, $CC);
  dma_wc             : ARRAY [0..7] OF
  BYTE = ($01, $03, $05, $07, $C2, $C6, $CA, $CE);

  snd_mono      = 0;
  snd_8bit      = 0;
  snd_nonsigned = 0;
  snd_stereo    = 1;
  snd_16bit     = 2;
  snd_signed    = 4;

  off = FALSE;
  on  = TRUE;

  { Constants for volume settings }
  master    = 1;
  voice     = 2;
  midi      = 3;
  cd        = 4;
  linein    = 5;
  mike      = 6;
  speaker   = 7;
  treble    = 8;
  bass      = 9;
  snd_left  = 1;
  snd_right = 2;

  { Constants for WAVe format types }
  fmt_unknown  = $0000;
  fmt_pcm      = $0001;
  fmt_msadpcm  = $0002;
  fmt_imaadpcm = $0011;

  buffersize  : WORD = 16104;  { Largest legal buffer value      }
  autorestore : BOOLEAN = TRUE;{ automatic restore mixersettings }
  surround    : BOOLEAN = FALSE;
  sb_errorstr : ARRAY [0..8] OF
  STRING[32] = ('No error',
            'No soundcard found',
            'Soundard not supported',
            'Soundcard busy',
            'File not found',
            'Compressed files not supported',
            'Format not supported',
            'File handle not valid',
            'Soundcard INT not responding');
  sb_noerror      = 0;
  sb_nocardfound  = 1;
  sb_notsupported = 2;
  sb_busy         = 3;
  sb_filenotfound = 4;
  sb_nocompressed = 5;
  sb_falseformat  = 6;
  sb_nohandles    = 7;
  sb_nointrespond = 8;

  soundlib_vstr = 'SoundLib 1.2b';
  soundlib_vnum = $012B;

VAR
  oldexitproc     : POINTER;

  blaster          : RECORD
                       irq         : BYTE;
                       lodma, hidma : WORD;
                       address      : WORD;
                       aweport     : WORD; { not really used by unit }
                       version     : WORD;
                       available   : BOOLEAN;
                       {following will be filled with the maximum playback values}
                       minfreq     : LONGINT;
                       monofreq,
                       stereofreq  : LONGINT;
                       sound16bit  : BOOLEAN;
                       stereo      : BOOLEAN;
                     END;

  play             : tplay;
  rec              : trec;
  dummy            : WORD;

  oldint           : POINTER;
  irqmsk, irqvec    : BYTE;
  dsbuf            : POINTER; { Buffer for downsampling }

FUNCTION  initblaster : BYTE;{call it _before_ any usage of the blaster}
FUNCTION  getblasterstring : STRING;
PROCEDURE initrecord (p : tmemp;
                      buffersize, frequency : WORD;
                      flags : WORD);
PROCEDURE initplay (datanum : BYTE;
                    p : tmemp;
                    buffersize, frequency : WORD;
                    flags : WORD);
PROCEDURE exitplay;{stop playback - use it only if you haven't used open****}
PROCEDURE exitrecord;
PROCEDURE pauserecord (pause : BOOLEAN);
PROCEDURE pauseplay (pause : BOOLEAN);
PROCEDURE startplay (datanum : BYTE);{start playback if you used open****}
PROCEDURE stopplay; {stop  playback if you used open****}
FUNCTION  getactpos : LONGINT;
PROCEDURE silence (VAR p;
                   count : WORD);
PROCEDURE setplaypos (datanum : BYTE;
                      POS : LONGINT);{set fileposition of playback file - only if you used open****}
FUNCTION  setagc (on : BOOLEAN) : BOOLEAN;
FUNCTION  setvolume (what, left, right : BYTE) : BOOLEAN;
FUNCTION  getvolume (what : BYTE;
                     VAR left, right : BYTE) : BOOLEAN;
FUNCTION  setoutput (output : BYTE;
                     left, right : BOOLEAN) : BOOLEAN;
FUNCTION  setinput (input, channel : BYTE;
                    left, right : BOOLEAN) : BOOLEAN;
FUNCTION  getinput (input, channel : BYTE;
                    VAR left, right : BOOLEAN) : BOOLEAN;
FUNCTION  setgain (out : BOOLEAN;
                   left, right : BYTE) : BOOLEAN;
FUNCTION  getgain (out : BOOLEAN;
                   VAR left, right : BYTE) : BOOLEAN;
FUNCTION  setmemsize (size : WORD) : BOOLEAN;
FUNCTION  openvoc (datanum : BYTE;
                   filename : STRING) : BYTE;
FUNCTION  openwav (datanum : BYTE;
                   filename : STRING) : BYTE;
FUNCTION  opensound (datanum : BYTE;
                     s : STRING) : BYTE;{open wave or vocfile -the program detects that with file extension}
PROCEDURE closesound (datanum : BYTE);{close playback file and stop playback}
PROCEDURE savemixer;
PROCEDURE restoremixer;
PROCEDURE error (num : BYTE);
VAR
  detectblaster : FUNCTION : BOOLEAN;

CONST
  errorproc : PROCEDURE (num : BYTE) = error;
{Change this if you have i.e. a GUI}

IMPLEMENTATION

FUNCTION  readmixer (reg : BYTE) : BYTE;
FORWARD;
PROCEDURE writemixer (reg, VAL : BYTE);
FORWARD;

PROCEDURE error (num : BYTE);
BEGIN
  ASM
  mov ax, 3;
  INT 10h END;
  WRITELN ('Error: ', sb_errorstr [num]);
  HALT;
END;

FUNCTION getblasterstring : STRING;
BEGIN
  WITH blaster DO
       BEGIN
       IF version >= sblive THEN
          getblasterstring := 'Soundblaster Live!'
       ELSE
       IF version >= sb16 THEN
          BEGIN
          IF aweport = 0 THEN
             getblasterstring := 'Soundblaster 16'
          ELSE
             getblasterstring := 'Soundblaster AWE32/64'
          END
       ELSE
       IF version >= sbpro20 THEN
          getblasterstring := 'Soundblaster Pro 2.0'
       ELSE
       IF version >= sbpro THEN
          getblasterstring := 'Soundblaster Pro'
       ELSE
       IF version >= sb21 THEN
          getblasterstring := 'Soundblaster 2.1'
       ELSE
       IF version >= sb20 THEN
          getblasterstring := 'Soundblaster 2.0';
       END;
END;

{procedure writedsp(v : byte);assembler;
asm
  mov   dx,blaster.address
  add   dx,0Ch
  xor   cx,cx
  @lp:
    in    al,dx
    dec   cx
  jz    @err
  cmp   al,127
  ja    @lp
  jmp   @noerr
  @err:
    push  sb_busy
    call  errorproc
  @noerr:
  mov   al,v
  out   dx,al
end;}

FUNCTION writedsp (v : BYTE) : BOOLEAN;
assembler;
ASM
  mov   dx, blaster.address
  add   dx, 0Ch
  XOR   cx, cx
  @lp :
  IN    al, dx
  DEC   cx
  jz    @err
  test  al, $80
  jnz   @lp
  jmp   @noerr
  @err :
  mov   al, 0
  jmp   @END
@noerr :
mov   al, v
out   dx, al
mov   al, 1
@END :
END;

FUNCTION readdsp : BYTE;
assembler;
ASM
  mov   dx, blaster.address
  add   dx, 0eh
  XOR   cx, cx
  @lp :
  IN    al, dx
  DEC   cx
  jz    @err
  test  al, $80
  jz    @lp
  jmp   @noerr
  @err :
  mov   al, 0
  jmp   @END
@noerr :

mov   dx, blaster.address
add   dx, 0Ah
IN    al, dx
@END :
END;


VAR
  endtime : LONGINT;

FUNCTION currenttime : LONGINT;
assembler;
ASM
  {$IFDEF VER60}
  mov   ax, $0040;
  mov   es, ax
  {$ELSE}
  mov   es, [seg0040]
  {$ENDIF}
  mov   ax, es : [6Ch]
  mov   dx, es : [6eh]
END;

{function resetblaster : boolean;
var
  b : byte;
begin
  port[blaster.address+$6] := 1;
  endtime := currenttime+3;
  while endtime > currenttime do;
  port[blaster.address+$6] := 0;
  endtime := currenttime+2;
  repeat
    b := port[blaster.address+$E];
    b := port[blaster.address+$A];
  until (b = $AA)or(currenttime >= endtime);
  resetblaster := b = $AA;
end;

procedure resetblaster_fast;
begin
  port[blaster.address+$6] := 1;
  port[blaster.address+$6] := 0;
end;}

FUNCTION resetblaster : BOOLEAN;
VAR
  b : BYTE;

BEGIN
  port [blaster.address + $6] := 1;
  endtime := currenttime + 2;
  WHILE (endtime > currenttime) DO
        ;
  port [blaster.address + $6] := 0;
  b := readdsp;
  {  endtime := currenttime+3;
  repeat
    b := inp(blaster.address+$E);
    b := inp(blaster.address+$A);
  until (b = $AA)or(currenttime >= endtime);}
  resetblaster := b = $AA;
END;



PROCEDURE setspeed (hz : BYTE);
assembler;
ASM
  mov    ax, 40h
  push   ax
  call   writedsp
  mov    al, hz
  DEC    al
  push   ax
  call   writedsp
END;

PROCEDURE setspeedSB16play (hz : WORD);
assembler;
ASM
  mov    ax, 42h
  push   ax
  call   writedsp
  mov    ax, hz
  mov    al, Ah
  XOR    Ah, Ah
  push   ax
  call   writedsp
  mov    ax, hz
  XOR    Ah, Ah
  push   ax
  call   writedsp
END;

PROCEDURE setspeedSB16record (hz : WORD);
assembler;
ASM
  mov    ax, 41h
  push   ax
  call   writedsp
  mov    ax, hz
  mov    al, Ah
  XOR    Ah, Ah
  push   ax
  call   writedsp
  mov    ax, hz
  XOR    Ah, Ah
  push   ax
  call   writedsp
END;

PROCEDURE setsamplingrate (hz : WORD);
BEGIN
  IF blaster.version >= sb16 THEN
     setspeedSB16play (hz)
  ELSE
     BEGIN
     IF blaster.version >= sbpro THEN
        setspeed (256 - (1000000 DIV (LONGINT (hz) * SUCC (BYTE (play.data [actfile] .stereo) ) ) ) )
     ELSE
        setspeed (256 - (1000000 DIV (LONGINT (hz) ) ) );
     IF hz < 36000 THEN
        BEGIN {Lowpass filter for better sound quality}
        writemixer ($0E, readmixer ($0E) AND NOT 32);
        IF hz < 18000 THEN
           writemixer ($0C, readmixer ($0C) AND NOT 8) {3,2 khz}
        ELSE
           writemixer ($0C, readmixer ($0C) OR 8); {8,8 khz-filter}
        END
     ELSE
        writemixer ($0E, readmixer ($0E) OR 32);
     END;
END;

PROCEDURE setsamplingraterec (hz : WORD);
BEGIN
  IF blaster.version >= sb16 THEN
     setspeedSB16record (hz)
  ELSE
     setspeed (256 - (1000000 DIV (LONGINT (hz) * SUCC (BYTE (rec.stereo) ) ) ) );
END;

PROCEDURE pauserecord (pause : BOOLEAN);
{Pause the recording - if you play at the same resolution
 (8 or 16 bit) as the recording, this procedure will pause
 both recording and playing}
BEGIN
  IF pause THEN
     BEGIN
     IF NOT rec.paused THEN
        IF (rec.sound16bit) AND (blaster.version >= sb16) THEN
           writedsp ($D5)
        ELSE
           writedsp ($D0);
     END
  ELSE
     BEGIN
     IF rec.paused THEN
        IF (rec.sound16bit) AND (blaster.version >= sb16) THEN
           writedsp ($D6)
        ELSE
           writedsp ($D4);
     END;
  rec.paused := pause;
END;

PROCEDURE pauseplay (pause : BOOLEAN);
{Pause the playback - if you record at the same resolution
 (8 or 16 bit) as the playing, this procedure will pause
 both recording and playing}
BEGIN
  IF pause THEN
     BEGIN
     IF NOT play.paused THEN
        IF (play.data [actfile] .sound16bit) AND (blaster.version >= sb16) THEN
           writedsp ($D5)
        ELSE
           writedsp ($D0);
     END
  ELSE
     BEGIN
     IF play.paused THEN
        IF (play.data [actfile] .sound16bit) AND (blaster.version >= sb16) THEN
           writedsp ($D6)
        ELSE
           writedsp ($D4);
     END;
  play.paused := pause;
END;


VAR
  settings1 : ARRAY [1..9] OF
  RECORD
    l, r : BYTE;
  END;
  settings2 : ARRAY [1..8] OF
  BYTE;

PROCEDURE savemixer;
BEGIN
  FOR dummy := 1 TO 9 DO
      getvolume (dummy, settings1 [dummy] .l, settings1 [dummy] .r);
  IF blaster.version >= sb16 THEN
     FOR dummy := 1 TO 8 DO
         settings2 [dummy] := readmixer ($3B + dummy)
  ELSE
  IF blaster.version >= sbpro THEN
     BEGIN
     settings2 [1] := readmixer ($0C);
     settings2 [2] := readmixer ($0E);
     END;
END;

PROCEDURE restoremixer;
BEGIN
  FOR dummy := 1 TO 9 DO
      setvolume (dummy, settings1 [dummy] .l, settings1 [dummy] .r);
  IF blaster.version >= sb16 THEN
     FOR dummy := 1 TO 8 DO
         writemixer ($3B + dummy, settings2 [dummy])
  ELSE
  IF blaster.version >= sbpro THEN
     BEGIN
     writemixer ($0C, settings2 [1]);
     writemixer ($0E, settings2 [2]);
     END;
END;

PROCEDURE exitblaster;
far;
BEGIN
  exitproc := oldexitproc;
  IF blaster.available THEN
     BEGIN
     IF NOT play.data [actfile] .fclosed THEN
        closesound (actfile);
     IF NOT rec.stopped THEN
        exitrecord;
     SETINTVEC (irqvec + (blaster.irq AND 7), oldint);
     IF blaster.irq < 8 THEN
        port [$21] := port [$21] OR irqmsk
     ELSE
        port [$A1] := port [$A1] OR irqmsk;
     writedsp ($D3);
     IF blaster.irq < 8 THEN
        port [$20] := $20
     ELSE
        port [$A0] := $20;
     IF autorestore THEN
        restoremixer;
     {$IFNDEF DPMI}
     FREEMEM (play.p, buffersize);
     {$ELSE}
     globaldosfree (play.p);
     {$ENDIF}
     FREEMEM (dsbuf, buffersize * 4);
     END;
END;

PROCEDURE initdma (dma : BYTE;
                   p : tmemp;
                   size : WORD;
                   get, autoinit : BOOLEAN);
VAR
  b : BYTE;
  l : LONGINT;
  segm, offs : WORD;
BEGIN
  {$IFNDEF DPMI}
  l := LONGINT (SEG (p^) ) SHL 4 + OFS (p^);
  {$ELSE}
  p := p AND $FFFF0000;
  l := ( (p AND $FFFF0000) SHR 16) SHL 4 + p AND $FFFF;
  {$ENDIF}
  segm := l SHR 16;
  IF dma > 3 THEN
     offs := WORD ( (LONGINT (p) AND $FFFF0000) SHR 13 + (LONGINT (p) AND $FFFF) SHR 1)
  ELSE
     offs := l AND $FFFF;

  IF get THEN
     b := $44
  ELSE
     b := $48;
  IF autoinit THEN
     INC (b, $10);

  IF dma > 3 THEN
     BEGIN
     port [$D4] := dma;
     port [$D6] := b + dma - 4;
     port [$D8] := 0;
     END
  ELSE
     BEGIN
     port [$0A] := dma + 4;
     port [$0B] := b + dma;
     port [$0C] := 0;
     END;
  port [dma_adr [dma] ] := LO (offs);
  port [dma_adr [dma] ] := HI (offs);
  port [dma_lpage [dma] ] := segm;
  port [dma_wc [dma] ] := LO (size - 1);
  port [dma_wc [dma] ] := HI (size - 1);
  IF dma > 3 THEN
     port [$D4] := dma - 4
  ELSE
     port [$0A] := dma;
END;

FUNCTION dmagetpos (dma : BYTE) : WORD;
VAR
  w : WORD;
BEGIN
  IF dma > 3 THEN
     port [$D8] := 0
  ELSE
     port [$0C] := 0;
  w := port [dma_wc [dma] ];
  w := WORD (port [dma_wc [dma] ]) SHL 8 + w;
  INC (w);
  IF dma > 3 THEN
     w := w SHL 1;
  dmagetpos := w;
END;

FUNCTION getactpos : LONGINT;
VAR
  dma : BYTE;
  l, l2 : LONGINT;
BEGIN
  IF (blaster.version >= sb16) AND (play.data [actfile] .sound16bit) THEN
     dma := blaster.hidma
  ELSE
     dma := blaster.lodma;
  l := (play.data [actfile] .fsize - play.data [actfile] .fileremain) +
  (buffersize - dmagetpos (dma) ) - PRED (play.activeblock) * play.blocksize - buffersize;
  l2 := play.data [actfile] .fsize - play.data [actfile] .fdatastart;
  IF l > l2 THEN
     l := l2;
  getactpos := l;
END;

PROCEDURE playsb (p : tmemp;
                  dsize : WORD);
BEGIN
  initdma (blaster.lodma, p, dsize, FALSE, FALSE);
  writedsp ($14);
  writedsp (LO (dsize - 1) );
  writedsp (HI (dsize - 1) );
END;

PROCEDURE initrecord (p : tmemp;
                      buffersize, frequency : WORD;
                      flags : WORD);
VAR
  size, dma : WORD;
BEGIN
  IF NOT blaster.available THEN
     EXIT;
  rec.sound16bit := flags AND snd_16bit <> 0;
  rec.stereo     := flags AND snd_stereo <> 0;
  rec.blocksize  := buffersize SHR 1;
  rec.frequency  := frequency;
  rec.p          := p;
  rec.activeblock := 2;{Block where the last data has been written to}
  rec.stopped    := FALSE;
  rec.hispeed    := FALSE;

  size := play.blocksize;

  setsamplingraterec (frequency);

  IF blaster.version >= sb16 THEN
     BEGIN
     size := rec.blocksize;
     IF rec.sound16bit THEN
        BEGIN
        size := size SHR 1;
        dma := blaster.hidma;
        END
     ELSE
        dma := blaster.lodma;

     initdma (dma, rec.p, size SHL 1, TRUE, TRUE);
     IF rec.sound16bit THEN
        BEGIN
        writedsp ($BE);
        IF rec.stereo THEN
           writedsp ($30)
        ELSE
           writedsp ($10);{signed!!!}
        END
     ELSE
        BEGIN
        writedsp ($CE);
        IF rec.stereo THEN
           writedsp ($20)
        ELSE
           writedsp ($00);
        END;
     writedsp (LO (size - 1) );
     writedsp (HI (size - 1) );
     END
  ELSE
  IF
     ( (blaster.version >= sb21) AND ( (rec.frequency > 13000) ) OR
       ( (blaster.version >= sbpro) AND ( (rec.frequency > 23000) OR (rec.stereo) ) ) ) THEN
     BEGIN
     {sb21 or higher and sr > 13000 or sbpro and sr > 23000}
     writedsp ($D3);
     rec.hispeed := TRUE;
     IF (rec.stereo) AND (blaster.version >= sbpro) THEN{sbpro and stereo and sr >= 11025 and sr <= 22050}
        writedsp ($A8);

     initdma (blaster.lodma, rec.p, size SHL 1, TRUE, TRUE);
     setsamplingrate (rec.frequency);

     writedsp ($48);
     writedsp (LO (size - 1) );
     writedsp (HI (size - 1) );
     writedsp ($98);
     END
  ELSE
     BEGIN {sb20 or higher, mono and sr <=13000}
     writedsp ($D3);
     initdma (blaster.lodma, rec.p, size SHL 1, TRUE, TRUE);
     setsamplingrate (rec.frequency);

     writedsp ($48);
     writedsp (LO (size - 1) );
     writedsp (HI (size - 1) );
     writedsp ($2C);
     END;
END;


PROCEDURE downsample8 (p1, p2 : POINTER;
                       adder, size : WORD);
far;
assembler;
ASM
  mov   cx, size
  OR    cx, cx
  jz    @END
push  ds
les   di, p1
lds   si, p2
mov   bx, adder
@lp :
mov   ax, es : [di]

mov   ds : [si], ax
add   di, bx
add   si, 2
DEC   cx
jnz   @lp
pop   ds
@END :
END;

PROCEDURE downsample8m (p1, p2 : POINTER;
                        adder, size : WORD);
far;
assembler;
ASM
  mov   cx, size
  SHL   cx, 1
  jz    @END
push  ds
les   di, p1
lds   si, p2
mov   bx, adder
SHR   bx, 1
XOR   dh, dh
@lp :
mov   ax, es : [di]
mov   dl, Ah
XOR   Ah, Ah
add   ax, dx
SHR   ax, 1

mov   ds : [si], al
add   di, bx
INC   si
DEC   cx
jnz   @lp
pop   ds
@END :
END;

PROCEDURE downsample16 (p1, p2 : POINTER;
                        adder, size : WORD);
far;
assembler;
ASM
  mov   cx, size
  OR    cx, cx
  jz    @END
push  ds
mov   bx, adder
les   di, p1
lds   si, p2
@lp :
mov   al, es : [di + 1]
mov   Ah, es : [di + 3]
add   al, $80
add   Ah, $80

mov   ds : [si], ax
add   di, bx
add   si, 2
DEC   cx
jnz   @lp
pop   ds
@END :
END;

PROCEDURE downsample16m (p1, p2 : POINTER;
                         adder, size : WORD);
far;
assembler;
ASM
  mov   cx, size
  SHL   cx, 1
  jz    @END
push  ds
mov   bx, adder
SHR   bx, 1
les   di, p1
lds   si, p2
@lp :
mov   Ah, es : [di + 1]
mov   dh, es : [di + 3]
sar   ax, 1
sar   ax, 1
sar   ax, 1
sar   ax, 1
sar   ax, 1
sar   ax, 1
sar   ax, 1
sar   ax, 1
sar   dx, 1
sar   dx, 1
sar   dx, 1
sar   dx, 1
sar   dx, 1
sar   dx, 1
sar   dx, 1
sar   dx, 1
add   ax, dx
sar   ax, 1
add   al, $80

mov   ds : [si], al
add   di, bx
INC   si
DEC   cx
jnz   @lp
pop   ds
@END :
END;

PROCEDURE surround16 (p : POINTER;
                      size : WORD);
assembler;
ASM
  mov   cx, size
  OR    cx, cx
  jz    @END
les   di, p
@lp :
mov   ax, es : [di]
neg   ax
mov   es : [di], ax
add   di, 4
DEC   cx
jnz   @lp
@END :
END;

PROCEDURE surround8 (p : POINTER;
                     size : WORD);
assembler;
ASM
  mov   cx, size
  OR    cx, cx
  jz    @END
les   di, p
@lp :
mov   al, es : [di]
neg   al
mov   es : [di], al
add   di, 2
DEC   cx
jnz   @lp
@END :
END;


VAR
  dummycalled : BOOLEAN;

PROCEDURE dummycaller;
far;
BEGIN
  dummycalled := TRUE;
END;


PROCEDURE exitplay;
BEGIN
  IF play.stopped THEN
     EXIT;
  IF blaster.version >= sb16 THEN
     BEGIN
     IF play.data [actfile] .sound16bit THEN
        writedsp ($D9)
     ELSE
        writedsp ($DA);
     resetblaster;
     END
  ELSE
  IF play.hispeed THEN
     BEGIN
     resetblaster;
     writedsp ($D3);
     writemixer ($E, readmixer ($E) AND NOT 2);
     END
  ELSE
     BEGIN
     writedsp ($D3);
     writedsp ($DA);
     resetblaster;
     END;
  play.stopped  := TRUE;
  play.callproc := dummycaller;
END;

PROCEDURE exitrecord;
BEGIN
  IF NOT rec.stopped THEN
     BEGIN
     IF blaster.version >= sb16 THEN
        BEGIN
        IF rec.sound16bit THEN
           writedsp ($D9)
        ELSE
           writedsp ($DA);
        resetblaster;
        END
     ELSE
     IF rec.hispeed THEN
        BEGIN
        resetblaster;
        writemixer ($E, readmixer ($E) AND NOT 2);
        END
     ELSE
        BEGIN
        writedsp ($DA);
        resetblaster;
        END;
     rec.stopped  := TRUE;
     rec.callproc := dummycaller;
     END;
END;


PROCEDURE silence (VAR p;
                   count : WORD);
  PROCEDURE fillword (VAR X;
                      count : WORD;
                      value : WORD);
  assembler;
  ASM
    les di, X;
    mov cx, count;
    mov ax, value;
    rep stosw;
  END;
BEGIN
  IF (play.data [actfile] .sound16bit) AND (blaster.sound16bit)
     THEN
     fillword (p, count SHR 1, 0)
  ELSE
     fillword (p, count SHR 1, $8080);
END;

VAR
  dsjump : WORD;
  downsample : PROCEDURE (p1, p2 : POINTER;
                          adder, size : WORD);

FUNCTION outofspec (freq : WORD;
                    stereo, sound16bit : BOOLEAN) : BOOLEAN;
BEGIN
  outofspec := TRUE;
  IF (LONGINT (freq) * 2 > blaster.monofreq) AND (NOT blaster.stereo) THEN
     EXIT;
  IF (stereo) AND (NOT blaster.stereo) THEN
     EXIT;
  IF (sound16bit) AND (NOT blaster.sound16bit) THEN
     EXIT;
  IF (stereo) AND (freq > blaster.stereofreq) THEN
     EXIT;
  IF (NOT stereo) AND (freq > blaster.monofreq) THEN
     EXIT;
  outofspec := FALSE;
END;

PROCEDURE READ (VAR f : FILE;
                p : POINTER;
                size, bsize : WORD);
VAR
  mem    : WORD;
  readen, io : WORD;
BEGIN
  {  writeln(size);}
  IF (blaster.version < sb16) THEN
     BEGIN
     IF outofspec (play.data [actfile] .frequency, play.data [actfile] .stereo,
                   play.data [actfile] .sound16bit) THEN
        BEGIN
        mem := size * (dsjump SHR 1);
        {$I-}
        BLOCKREAD (f, dsbuf^, mem, readen);
        {$I+}
        io := IORESULT;
        downsample (dsbuf, p, dsjump, size SHR 1);
        DEC (play.data [actfile] .fileremain, mem);
        END
     ELSE
        BEGIN
        BLOCKREAD (f, p^, size, readen);
        DEC (play.data [actfile] .fileremain, size);
        IF (play.data [actfile] .stereo) AND (surround) AND (blaster.version >= sbpro) THEN
           surround8 (p, size SHR 1);
        END;
     END
  ELSE
     BEGIN
     {$I-}
     BLOCKREAD (f, p^, size, readen);
     {$I+}
     io := IORESULT;
     DEC (play.data [actfile] .fileremain, readen);
     IF (play.data [actfile] .stereo) AND (surround) AND (blaster.version >= sbpro) THEN
        BEGIN
        IF play.data [actfile] .sound16bit THEN
           surround16 (p, size SHR 2)
        ELSE
           surround8 (p, size SHR 1);
        END;
     END;
  IF readen < bsize THEN
     silence (PTR (SEG (p^), OFS (p^) + (readen AND NOT 1) ) ^, bsize - readen);
END;

VAR
  lastblock : BOOLEAN; { Crappy solution... but works ;) }

PROCEDURE soundplaycaller;
far;
VAR
  p    : POINTER;
  size : WORD;
BEGIN
  IF (play.data [actfile] .fileremain > 0) THEN
     BEGIN
     size := play.blocksize;
     IF (size > play.data [actfile] .fileremain) THEN
        size := play.data [actfile] .fileremain;
     {$IFNDEF DPMI}
     READ (play.data [actfile] .f,
           PTR (SEG (play.p^), OFS (play.p^) + play.blocksize * PRED (play.activeblock) ),
           size,
           play.blocksize);
     {$ELSE}
     READ (play.data [actfile] .f,
           PTR (play.p AND $FFFF, play.blocksize * PRED (play.activeblock) ),
           size,
           play.blocksize);
     {$ENDIF}
     IF play.activeblock = 2 THEN
        play.activeblock := 1
     ELSE
        play.activeblock := 2;
     lastblock := FALSE;
     END
  ELSE
  IF NOT lastblock THEN
     lastblock := TRUE
  ELSE
     exitplay;
END;

{$IFDEF REENTRANT}
VAR
  intrunning : BOOLEAN;
{$ENDIF}

PROCEDURE intcaller;INTERRUPT;
{
For slow machines, or for trying to do something else at the
same time the sound is playing, we need to enable interrupts quickly.
}
VAR
  h   : BYTE;
{$IFDEF REENTRANT}
  run : BOOLEAN;
{$ENDIF}
BEGIN
  {$IFDEF REENTRANT}
  run := intrunning;
  intrunning := TRUE;
  {$ENDIF}
  {acknowledge the Sound Blaster:}
  IF blaster.version >= sb16 THEN BEGIN
    h := readmixer ($82);
    IF h AND 1 <> 0
      THEN h := port [blaster.address + $E]
      ELSE h := port [blaster.address + $F];
  end else begin {not sb16, so do this instead:}
    h := port [blaster.address + $E];
  end;
  {$IFDEF REENTRANT}
  IF NOT run THEN {If interrupts overlap, the machine may hang!}
  {$ENDIF}
  begin
    {$IFDEF LONGINTR}
    {now that we're done aknowledging the SB, release interrupts immediately}
    IF blaster.irq > 7 THEN port [$A0] := $20;
    port [$20] := $20; {signal PIC we're finished}
    asm sti end;
    {$ENDIF}
    IF NOT rec.stopped THEN rec.callproc;
    IF NOT play.stopped THEN play.callproc;
  END;
  {$IFNDEF LONGINTR}
  IF blaster.irq > 7 THEN port [$A0] := $20;
  port [$20] := $20; {signal PIC we're finished}
  {$ENDIF}
  {$IFDEF REENTRANT}
  intrunning := FALSE;
  {$ENDIF}
END;

FUNCTION hex2word (s : STRING) : WORD;
CONST
  number : SET OF
  CHAR = ['0'..'9'];
VAR
  i    : WORD;
  w, w2 : WORD;
BEGIN
  w := 0;
  FOR i := 1 TO LENGTH (s) DO
      BEGIN
      IF s [i] IN number THEN
         w2 := ORD (s [i]) - 48
      ELSE
         w2 := ORD (s [i]) - 55;
      INC (w, w2 SHL ( (LENGTH (s) - i) * 4) );
      END;
  hex2word := w;
END;

FUNCTION getdspversion : WORD;
assembler;
ASM
  mov    ax, $E1
  push   ax
  call   writedsp
  mov    dx, blaster.address
  add    dx, 0Ah
  @lp1 :
  IN    al, dx
  cmp   al, $AA
  mov   Ah, al
  je @lp1
  @lp2 :
  IN    al, dx
  cmp   al, $AA
  je @lp2
END;

FUNCTION detectawe32 (baseport : WORD) : BOOLEAN;
VAR
  scratch, tmp : WORD;
BEGIN
  detectawe32 := FALSE;
  portw [$0E02 + baseport] := 224;
  tmp := portw [$0E00 + baseport];
  scratch := portw [$0E00 + baseport];
  IF scratch AND $000F <> $0C THEN
     EXIT;
  portw [$0E02 + baseport] := 32 + 29;
  scratch := portw [$0A00 + baseport];
  IF scratch AND $007E <> $58 THEN
     EXIT;
  portw [$0E02 + baseport] := 32 + 30;
  scratch := portw [$0A00 + baseport];
  IF scratch AND $0003 <> $03 THEN
     EXIT;
  detectawe32 := TRUE;
END;

FUNCTION detectblaster_norm : BOOLEAN;
far;
VAR
  s, s2 : STRING;
  i    : WORD;
  i2   : INTEGER;
BEGIN
  detectblaster_norm := FALSE;
  s := getenv ('BLASTER');
  IF s = '' THEN
     EXIT;              {No blaster environment string...}
  FOR i := 1 TO LENGTH (s)
      DO
      s [i] := UPCASE (s [i]);

  i := POS ('D', s);
  IF i <> 0 THEN
     BEGIN
     VAL (s [i + 1], i, i2);
     blaster.lodma := i;
     END
  ELSE
     EXIT;
  i := POS ('H', s);
  IF i <> 0 THEN
     BEGIN
     VAL (s [i + 1], i, i2);
     blaster.hidma := i;
     END
  ELSE
     blaster.version := sbpro;

  i := POS ('I', s);
  IF i <> 0 THEN
     BEGIN
     VAL (s [i + 1], i, i2);
     blaster.irq := i;
     i := POS ('I', s);
     IF (i + 2 <= LENGTH (s) ) AND (s [i + 2] <> ' ') THEN
        BEGIN
        blaster.irq := blaster.irq * 10;
        VAL (s [i + 2], i, i2);
        INC (blaster.irq, i);
        END;
     END
  ELSE
     EXIT;

  i := POS ('A', s);
  IF i <> 0 THEN
     BEGIN
     FOR i2 := 1 TO 3 DO
         s2 [i2] := s [i + i2];
     s2 [0] := #3;
     s2 [4] := #0;
     blaster.address := hex2word (s2);
     END
  ELSE
     EXIT;

  detectblaster_norm := TRUE;
END;

(*function detectblaster_auto : boolean;far;
{I suggest to not use this, I was simply to lazy
 to improve the routine yet...                  }
var
  i : integer;
  temp1,temp2,pic1,pic2,x : byte;
begin
  detectblaster_auto := false;
  blaster.address := $200;
  for i := 0 to 8 do begin
    if not resetblaster then
    inc(blaster.address,$10) else break;
  end;
  if blaster.address = $290 then begin
    blaster.address := 0;
    exit;
  end;

  temp1 := port[$21];
  temp2 := port[$A1];
  port[$21] := temp1 or $A4;
  port[$A1] := temp2 or 4;
  writedsp($40);
  writedsp($D2);
  writedsp($80); { silent block }
  writedsp(1);
  writedsp(0);

  port[$20] := $A;
  port[$A0] := $A;
  pic1 := 0;
  pic2 := 0;
  i := 0;
  endtime := currenttime+18;
  repeat
    pic1 := port[$20] and $A0;
    pic2 := port[$A0] and $6;
  until ((pic1 <> 0)or(pic2 <> 0))or(endtime <= currenttime);

  i := port[blaster.address+$0E];
  if (pic1 = 0)and(pic2 = 0) then begin
    blaster.irq := 0;
    exit;
  end;
  port[$21] := temp1;
  port[$A1] := temp2;
  blaster.irq := 0;
  if pic2 <> 0 then begin
    blaster.irq := 7;
    while pic2 and 1 = 0 do begin
      inc(blaster.irq);
      pic2 := pic2 shr 1;
    end;
  end else
  while pic1 and 1 = 0 do begin
    inc(blaster.irq);
    pic1 := pic1 shr 1;
  end;

  writedsp($D3);
  writedsp($D0);
  writedsp($DA);
  resetblaster;

  port[$F] := $FF;
  writedsp($40);
  writedsp($D2);
  writedsp($14); { single block/dma }
  writedsp(1);
  writedsp(0);
  endtime := currenttime+18;
  repeat
    x := port[8] and $F0;
  until (x <> 0)or(endtime <= currenttime);
  blaster.lodma := 0;
  if x = 0 then exit;
  x := x shr 4;
  while x and 1 = 0 do begin
    inc(blaster.lodma);
    x := x shr 1;
  end;

  writedsp($D3);
  writedsp($D0);
  writedsp($DA);
  resetblaster;


{  blaster.irq := 7;}
{  blaster.lodma := 1;}
  blaster.hidma := 5;
  detectblaster_auto := true;
end;*)

FUNCTION initblaster : BYTE;
VAR
  i      : INTEGER;
  p, oldp : tmemp;
BEGIN
  IF blaster.available THEN
     BEGIN
     initblaster := sb_noerror;
     EXIT;
     END
  ELSE
     initblaster := sb_nocardfound;
  blaster.version := 0;

  IF NOT detectblaster THEN
     EXIT;

  IF NOT resetblaster THEN
     BEGIN { if blaster could not be resetted, }
     initblaster := sb_busy;     { it must be busy                   }
     EXIT;
     END;
  i := getdspversion;
  IF blaster.version = 0 THEN
     blaster.version := i
  ELSE
  IF blaster.version < sb16 THEN
     blaster.version := i;
  {for any tests with lower blaster versions, change here the version}
  {  blaster.version := sbpro;}
  IF blaster.version < sb20 THEN
     BEGIN        {blasters lower than version }
     initblaster := sb_notsupported;           {2.0 aren't supported because}
     EXIT;                                     {they cannot run the autoinit}
     END;                                        {mode - quality is too low   }

  WITH blaster DO
       BEGIN
       IF version >= sblive THEN
          BEGIN
          minfreq    := 5000;
          monofreq   := 48000;
          stereofreq := 48000;
          sound16bit := TRUE;
          stereo     := TRUE;
          aweport    := 0;
          END
       ELSE
       IF version >= sb16 THEN
          BEGIN
          minfreq    := 5000;
          monofreq   := 45000;
          stereofreq := 45000;
          sound16bit := TRUE;
          stereo     := TRUE;
          aweport    := 0;
          FOR i := 0 TO 4 DO
              IF
                 detectawe32 (i * $20) THEN
                 aweport := $600 + i * $20;
          END
       ELSE
       IF version >= sbpro20 THEN
          BEGIN
          minfreq    := 4000;
          monofreq   := 44100;
          stereofreq := 44100;
          sound16bit := FALSE;
          stereo     := TRUE;
          END
       ELSE
       IF version >= sbpro THEN
          BEGIN
          minfreq    := 4000;
          monofreq   := 44100;
          stereofreq := 22050;
          sound16bit := FALSE;
          stereo     := TRUE;
          END
       ELSE
       IF version >= sb21 THEN
          BEGIN
          minfreq    := 4000;
          monofreq   := 44100;
          stereofreq := 0;
          sound16bit := FALSE;
          stereo     := FALSE;
          END
       ELSE
          BEGIN
          minfreq    := 4000;
          monofreq   := 23000;
          stereofreq := 0;
          sound16bit := FALSE;
          stereo    := FALSE;
          END;
       END;
  IF blaster.irq < 8 THEN
     irqvec := $8
  ELSE
     irqvec := $70;
  GETINTVEC (irqvec + (blaster.irq AND 7), oldint);
  SETINTVEC (irqvec + (blaster.irq AND 7), @intcaller);
  irqmsk := 1 SHL (blaster.irq AND 7);
  IF blaster.irq < 8 THEN
     port [$21] := port [$21] AND NOT irqmsk
  ELSE
     port [$A1] := port [$A1] AND NOT irqmsk;
  blaster.available := TRUE;
  {Test if SB works}
  dummycalled   := FALSE;
  play.callproc := dummycaller;

  {$IFNDEF DPMI}
  GETMEM (p, $100);
  FILLCHAR (p^, $100, $80);
  {$ELSE}
  p := globaldosalloc ($100);
  FILLCHAR (PTR (p, 0) ^, $100, $7F);
  {$ENDIF}
  oldp := play.p;
  initplay (0, p, $100, 22050, snd_8bit + snd_mono + snd_nonsigned);
  endtime := currenttime + 5;
  WHILE (NOT dummycalled) AND (currenttime < endtime) DO
        ;
  IF NOT dummycalled THEN
     BEGIN
     initblaster := sb_nointrespond;
     blaster.available := FALSE;
     {$IFNDEF DPMI}
     FREEMEM (p, $100);
     {$ELSE}
     globaldosfree (p);
     {$ENDIF}
     play.p := oldp;
     EXIT;
     END;
  resetblaster;
  {$IFNDEF DPMI}
  FREEMEM (p, $100);
  {$ELSE}
  globaldosfree (p);
  {$ENDIF}
  exitplay;
  play.p := oldp;
  (*  dummycalled   := false;
  play.callproc := dummycaller;
  play.stopped  := false;
  writedsp($40);
  writedsp($D2);
  writedsp($80); { silent block }
  writedsp(1);
  writedsp(0);
  endtime := currenttime+4;
  while (not dummycalled)and(currenttime < endtime) do;
  if not dummycalled then begin
     initblaster := sb_busy;
     exit;
  end;
  resetblaster;*)

  {end of test}
  play.stopped     := TRUE;
  initblaster      := sb_noerror;
  savemixer;{save mixer settings}
END;



PROCEDURE writemixer (reg, VAL : BYTE);
assembler;
ASM
  mov   dx, blaster.address
  add   dx, 04h
  mov   al, reg
  out   dx, al
  INC   dx
  mov   al, VAL
  out   dx, al
END;

FUNCTION readmixer (reg : BYTE) : BYTE;
assembler;
ASM
  mov   dx, blaster.address
  add   dx, 04h
  mov   al, reg
  out   dx, al
  INC   dx
  IN    al, dx
END;

FUNCTION setagc (on : BOOLEAN) : BOOLEAN;
BEGIN
  setagc := FALSE;
  IF blaster.version < sb16 THEN
     EXIT
  ELSE
     setagc := TRUE;
  writemixer ($43, readmixer ($43) OR BYTE (on) );
END;

FUNCTION setoutput (output : BYTE;
                    left, right : BOOLEAN) : BOOLEAN;
  PROCEDURE setbit (bit : BYTE;
                    on : BOOLEAN);
  BEGIN
    IF on THEN
       writemixer ($3C, readmixer ($3C) OR 1 SHL bit)
    ELSE
       writemixer ($3C, readmixer ($3C) AND NOT (1 SHL bit) );
  END;

BEGIN
  setoutput := FALSE;
  IF blaster.version < sb16 THEN
     EXIT;
  CASE output OF
       mike : setbit (0, left);
       cd   : BEGIN
              ;
              setbit (1, right);
              setbit (2, left);
              END;
       linein : BEGIN
                ;
                setbit (3, right);
                setbit (4, left);
                END;
  ELSE
       EXIT;
  END;
  setoutput := TRUE;
END;

FUNCTION setinput (input, channel : BYTE;
                   left, right : BOOLEAN) : BOOLEAN;
{How to use this function?
 -channel is 1 for left, 2 for right
 -you can switch the input for left _and_ right for one channel
 -if you record mono, the left configuration will be used -
  so if you wanna record both left and right in mono, switch
  channel 1(left) to left and right
 -if the blaster is sbpro - you can't set anything off -
  only one thing on with the call you will set the called input on}
  PROCEDURE setbit (reg, bit : BYTE;
                    left, right : BOOLEAN);
  BEGIN
    IF bit = 0 THEN
       right := left;
    IF right THEN
       writemixer (reg, readmixer (reg) OR 1 SHL bit)
    ELSE
       writemixer (reg, readmixer (reg) AND NOT (1 SHL bit) );

    IF bit > 0 THEN
       IF left THEN
          writemixer (reg, readmixer (reg) OR 1 SHL SUCC (bit) )
       ELSE
          writemixer (reg, readmixer (reg) AND NOT (1 SHL SUCC (bit) ) );
  END;

VAR
  b : BYTE;
BEGIN
  setinput := FALSE;
  IF blaster.version >= sb16 THEN
     BEGIN
     b := channel + $3C;
     CASE input OF
          mike : setbit (b, 0, left, FALSE);
          cd   : setbit (b, 1, left, right);
          linein : setbit (b, 3, left, right);
          midi : setbit (b, 5, left, right);
     ELSE
          EXIT;
     END;
     END
  ELSE
  IF (blaster.version >= sbpro) AND ( (left) OR (right) ) THEN
     BEGIN
     CASE input OF
          cd   : b := 1;
          mike : b := 2;
          linein : b := 3;
     ELSE
          EXIT;
     END;
     writemixer ($0C, readmixer ($0C) OR (b SHL 1) );
     END
  ELSE
     EXIT;
  setinput := TRUE;
END;

FUNCTION getinput (input, channel : BYTE;
                   VAR left, right : BOOLEAN) : BOOLEAN;
  PROCEDURE getbit (reg, bit : BYTE;
                    VAR left, right : BOOLEAN);
  BEGIN
    BYTE (right) := (readmixer (reg) AND (1 SHL bit) ) SHR bit;
    IF bit > 0 THEN
       BYTE (left) := (readmixer (reg) AND (1 SHL SUCC (bit) ) ) SHR SUCC (bit);
    IF bit = 0 THEN
       left := right;
  END;

VAR
  b, b2 : BYTE;

BEGIN
  getinput := FALSE;
  IF blaster.version >= sb16 THEN
     BEGIN
     b := channel + $3C;
     CASE input OF
          mike : getbit (b, 0, left, right);
          cd   : getbit (b, 1, left, right);
          linein : getbit (b, 3, left, right);
          midi : getbit (b, 5, left, right);
     ELSE
          EXIT;
     END;
     END
  ELSE
  IF blaster.version >= sbpro THEN
     BEGIN
     b2 := readmixer ($0C) SHR 1 AND 3;
     CASE input OF
          cd   : b := 1;
          mike : b := 2;
          linein : b := 3;
     ELSE
          EXIT;
     END;
     left := b2 = b;
     END
  ELSE
     EXIT;
  getinput := TRUE;
END;


FUNCTION setgain (out : BOOLEAN;
                  left, right : BYTE) : BOOLEAN;
{This function controls the amplify of the sb16
 set out to true if you want to amplify the output
 else for the input set it false.
 The maximum size for left and right is 3!}
VAR
  b : BYTE;
BEGIN
  setgain := FALSE;
  IF blaster.version >= sb16 THEN
     BEGIN
     IF out THEN
        b := $41
     ELSE
        b := $3F;
     writemixer (b, left SHL 6);
     writemixer (b + 1, right SHL 6);
     setgain := TRUE;
     END;
END;

FUNCTION getgain (out : BOOLEAN;
                  VAR left, right : BYTE) : BOOLEAN;
VAR
  b : BYTE;
BEGIN
  getgain := FALSE;
  IF blaster.version >= sb16 THEN
     BEGIN
     IF out THEN
        b := $41
     ELSE
        b := $3F;
     left := readmixer (b) SHR 6;
     right := readmixer (b + 1) SHR 6;
     getgain := TRUE;
     END;
END;

FUNCTION setvolume (what, left, right : BYTE) : BOOLEAN;
{Maximum for left and right is 63. I know that this
 resolution is higher as the res of the sb. This
 is only for future versions of the sb - you have
 not to reprogram all things for volume settings!
 If the playback is mono, then the left volume will
 be used. The procedure returns false if the volume
 couldn't be setted (the soundcard doesn't support
 this volume type then)}
  PROCEDURE setvol (reg, left, right : BYTE);
  BEGIN
    IF blaster.version >= sb16 THEN
       BEGIN
       writemixer (reg, left);
       IF (reg <> $3A) AND (reg <> $3B) THEN
          writemixer (reg + 1, right);
       END
    ELSE
    IF blaster.version >= sbpro THEN
       BEGIN
       writemixer (reg, left SHL 4 OR right);
       END
    ELSE
       BEGIN
       IF (reg = $0A) OR (reg = $0B) THEN
          left := left SHR 1;
       writemixer (reg, left);
       END;
  END;

BEGIN
  IF left  > 63 THEN
     left  := 63;
  IF right > 63 THEN
     right := 63;
  left  := left  SHR 1;
  right := right SHR 1;
  setvolume := TRUE;
  IF blaster.version >= sb16 THEN
     BEGIN
     left  := left  SHL 3;
     right := right SHL 3;
     CASE what OF
          master  : setvol ($30, left, right);
          voice   : setvol ($32, left, right);
          midi    : setvol ($34, left, right);
          cd      : setvol ($36, left, right);
          linein  : setvol ($38, left, right);
          mike    : setvol ($3A, left, 0);
          speaker : setvol ($3B, left, 0);
          treble  : setvol ($44, left, right);
          bass    : setvol ($46, left, right);
     ELSE
          setvolume := FALSE;
     END;
     END
  ELSE
  IF blaster.version >= sbpro THEN
     BEGIN
     left  := left  SHR 1;
     right := right SHR 1;
     CASE what OF
          master  : setvol ($22, left, right);
          voice   : setvol ($04, left, right);
          midi    : setvol ($26, left, right);
          cd      : setvol ($28, left, right);
          linein  : setvol ($2E, left, right);
     ELSE
          setvolume := FALSE;
     END;
     END
  ELSE
     BEGIN
     left  := left SHR 2;
     CASE what OF
          master  : setvol ($02, left, 0);
          voice   : setvol ($0A, left, 0);
          midi    : setvol ($06, left, 0);
          cd      : setvol ($08, left, 0);
     ELSE
          setvolume := FALSE;
     END;
     END;
END;


FUNCTION getvolume (what : BYTE;
                    VAR left, right : BYTE) : BOOLEAN;
  PROCEDURE getvol (reg : BYTE;
                    VAR left, right : BYTE);
  BEGIN
    IF blaster.version >= sb16 THEN
       BEGIN
       left := readmixer (reg);
       IF (reg <> $3A) AND (reg <> $3B) THEN
          right := readmixer (reg + 1)
       ELSE
          right := left;
       END
    ELSE
    IF blaster.version >= sbpro THEN
       BEGIN
       left  := readmixer (reg);
       right := left AND $0F;
       left  := left SHR 4;
       END
    ELSE
       left := readmixer (reg);
    IF reg = $0A THEN
       left := left SHR 1;
  END;

BEGIN
  getvolume := TRUE;
  IF blaster.version >= sb16 THEN
     BEGIN
     CASE what OF
          master  : getvol ($30, left, right);
          voice   : getvol ($32, left, right);
          midi    : getvol ($34, left, right);
          cd      : getvol ($36, left, right);
          linein  : getvol ($38, left, right);
          mike    : getvol ($3A, left, right);
          speaker : getvol ($3B, left, right);
          treble  : getvol ($44, left, right);
          bass    : getvol ($46, left, right);
     ELSE
          getvolume := FALSE;
     END;
     left  := left  SHR 2;
     right := right SHR 2;
     END
  ELSE
  IF blaster.version >= sbpro THEN
     BEGIN
     CASE what OF
          master  : getvol ($22, left, right);
          voice   : getvol ($04, left, right);
          midi    : getvol ($26, left, right);
          cd      : getvol ($28, left, right);
          linein  : getvol ($2E, left, right);
     ELSE
          getvolume := FALSE;
     END;
     left  := left  SHL 2;
     right := right SHL 2;
     END
  ELSE
     BEGIN
     CASE what OF
          master  : getvol ($02, left, right);
          voice   : getvol ($0A, left, right);
          midi    : getvol ($06, left, right);
          cd      : getvol ($08, left, right);
     ELSE
          getvolume := FALSE;
     END;
     left  := left SHL 3;
     right := left;
     END;
END;


PROCEDURE initplay (datanum : BYTE;
                    p : tmemp;
                    buffersize, frequency : WORD;
                    flags : WORD);
VAR
  size, dma     : WORD;
  savecallproc : PROCEDURE;
BEGIN
  IF NOT blaster.available THEN
     EXIT;
  play.data [datanum] .sound16bit := flags AND snd_16bit <> 0;
  play.data [datanum] .stereo     := flags AND snd_stereo <> 0;
  play.blocksize  := buffersize SHR 1;
  play.data [datanum] .frequency  := frequency;
  play.p          := p;
  play.activeblock := 1;
  play.stopped    := FALSE;
  play.hispeed    := FALSE;

  size := play.blocksize;
  IF blaster.version >= sb16 THEN
     BEGIN
     setsamplingrate (play.data [datanum] .frequency);

     IF play.data [datanum] .sound16bit THEN
        BEGIN
        size := size SHR 1;
        dma := blaster.hidma;
        END
     ELSE
        dma := blaster.lodma;

     initdma (dma, play.p, size SHL 1, FALSE, TRUE);
     IF play.data [datanum] .sound16bit THEN
        writedsp ($B6)
     ELSE
        writedsp ($C6);
     IF play.data [datanum] .signed THEN
        BEGIN
        IF play.data [datanum] .stereo THEN
           writedsp ($30)
        ELSE
           writedsp ($10) END
     ELSE
        BEGIN
        IF play.data [datanum] .stereo THEN
           writedsp ($20)
        ELSE
           writedsp ($00);
        END;
     writedsp (LO (size - 1) );
     writedsp (HI (size - 1) );
     END
  ELSE
  IF (blaster.version >= sb21)
  AND ( (play.data [datanum] .frequency > 23000)
  OR (play.data [datanum] .stereo) ) THEN
     BEGIN{sb21 or higher and sr > 23000}
     writedsp ($D1);
     play.hispeed := TRUE;
     IF (play.data [datanum] .stereo) AND (blaster.version >= sbpro) THEN
        BEGIN{sbpro and stereo and sr >= 11025 and sr <= 22050}
        {This part switches the sbpro to stereo mode
       This should work according to the manual from
       creative labs}
        writemixer ($E, readmixer ($E) OR 2);
        savecallproc  := play.callproc;
        dummycalled   := FALSE;
        play.callproc := dummycaller;
        {$IFNDEF DPMI}
        dummy := $80;
        playsb (@dummy, 1);
        {$ELSE}
        mem [play.p AND $FFFF : 0] := $80;
        playsb (play.p, 1);
        {$ENDIF}
        REPEAT
        UNTIL dummycalled;
        play.callproc := savecallproc;
        END;

     initdma (blaster.lodma, play.p, size SHL 1, FALSE, TRUE);
     setsamplingrate (play.data [datanum] .frequency);

     writedsp ($48);
     writedsp (LO (size - 1) );
     writedsp (HI (size - 1) );
     writedsp ($90);
     END
  ELSE
     BEGIN {sb20 or higher, mono and sr <=23000}
     writedsp ($D1);
     initdma (blaster.lodma, play.p, size SHL 1, FALSE, TRUE);
     setsamplingrate (play.data [datanum] .frequency);
     IF play.data [datanum] .stereo THEN
        writemixer ($0E, readmixer ($0E) OR $20);
     writedsp ($48);
     writedsp (LO (size - 1) );
     writedsp (HI (size - 1) );
     writedsp ($1C);
     END;
END;


FUNCTION setdownsample (freq : WORD;
                        stereo, sound16bit : BOOLEAN) : WORD;
VAR
  maxsr : WORD;
BEGIN
  dsjump := 2;
  IF sound16bit THEN
     dsjump := dsjump SHL 1;

  IF (stereo) AND (NOT blaster.stereo) THEN
     BEGIN
     dsjump := dsjump SHL 1;
     IF sound16bit THEN
        downsample := downsample16m
     ELSE
        downsample := downsample8m;
     END
  ELSE
     BEGIN
     IF sound16bit THEN
        downsample := downsample16
     ELSE
        downsample := downsample8;
     END;

  IF (stereo) AND (blaster.stereo) THEN
     maxsr := blaster.stereofreq
  ELSE
     maxsr := blaster.monofreq;
  {!!  while (freq > maxsr) do
  begin
    freq := freq shr 1;
    dsjump := dsjump shl 1;
  end;}
  setdownsample := freq;
END;

PROCEDURE startplay (datanum : BYTE);
VAR
  size, freq : WORD;
  flags     : WORD;
BEGIN
  IF NOT play.stopped THEN
     EXIT;
  play.blocksize := buffersize SHR 1;
  actfile := datanum;
  SEEK (play.data [datanum] .f, play.data [datanum] .fdatastart);
  freq := setdownsample (play.data [actfile] .frequency, play.data [actfile] .stereo,
                         play.data [actfile] .sound16bit);
  IF play.data [datanum] .fdatasize < buffersize THEN
     BEGIN
     {$IFNDEF DPMI}
     silence (play.p^, buffersize);
     {$ELSE}
     silence (PTR (play.p AND $FFFF, 0) ^, buffersize);
     {$ENDIF}
     play.data [datanum] .fileremain := play.data [datanum] .fdatasize;
     IF play.data [datanum] .fdatasize > play.blocksize
        THEN
        size := play.blocksize
     ELSE
        size := play.data [datanum] .fdatasize;

     {$IFNDEF DPMI}
     READ (play.data [datanum] .f, play.p, size, play.blocksize);
     {$ELSE}
     READ (play.data [datanum] .f, PTR (play.p AND $FFFF, 0), size, play.blocksize);
     {$ENDIF}

     IF play.data [datanum] .fdatasize > play.blocksize THEN
     {$IFNDEF DPMI}
     READ (play.data [datanum] .f,
           PTR (SEG (play.p^), OFS (play.p^) + play.blocksize),
           play.data [datanum] .fileremain,
           play.blocksize);
     {$ELSE}
     READ (play.data [datanum] .f,
           PTR (play.p AND $FFFF, play.blocksize),
           play.data [datanum] .fileremain,
           play.blocksize);
     {$ENDIF}
     END
  ELSE
     BEGIN
     play.data [datanum] .fileremain := play.data [datanum] .fdatasize;
     {$IFNDEF DPMI}
     READ (play.data [datanum] .f, play.p, play.blocksize, play.blocksize);
     READ (play.data [datanum] .f, PTR (SEG (play.p^), OFS (play.p^) + play.blocksize), play.blocksize, play.blocksize);
     {$ELSE}
     READ (play.data [datanum] .f, PTR (play.p AND $FFFF, 0), play.blocksize, play.blocksize);
     READ (play.data [datanum] .f, PTR (play.p AND $FFFF, play.blocksize), play.blocksize, play.blocksize);
     {$ENDIF}
     END;
  play.paused := FALSE;
  play.callproc := soundplaycaller;
  IF play.data [datanum] .stereo THEN
     flags := snd_stereo
  ELSE
     flags := snd_mono;
  IF play.data [datanum] .sound16bit THEN
     flags := flags OR snd_16bit
  ELSE
     flags := flags OR snd_8bit;
  WITH play DO
       initplay (datanum, p, blocksize SHL 1, freq, flags);
END;

PROCEDURE stopplay;
BEGIN
  IF NOT play.stopped THEN
     BEGIN
     exitplay;
     play.stopped := TRUE;
     END;
END;


PROCEDURE setplaypos (datanum : BYTE;
                      POS : LONGINT);
BEGIN
  SEEK (play.data [datanum] .f, POS);
  play.data [actfile] .fileremain := play.data [actfile] .fsize - play.data [actfile] .fdatastart - POS;
END;

FUNCTION setmemsize (size : WORD) : BOOLEAN;
BEGIN
  IF (size <= 16107) AND (size >= 256) AND (play.stopped) THEN
     BEGIN
     size := size AND $FFFC; {must be divideable by four!}
     IF dsbuf <> NIL THEN
        FREEMEM (dsbuf, buffersize * 4);
     GETMEM (dsbuf, size * 4);
     {$IFNDEF DPMI}
     IF play.p <> NIL THEN
        FREEMEM (play.p, buffersize);
     buffersize := size;
     GETMEM (play.p, buffersize);
     {$ELSE}
     globaldosfree (play.p);
     buffersize := size;
     play.p := globaldosalloc (buffersize);
     {$ENDIF}
     setmemsize := TRUE;
     END
  ELSE
     setmemsize := FALSE;
END;

VAR
  lastfilemode : BYTE;

FUNCTION openvoc (datanum : BYTE;
                  filename : STRING) : BYTE;
{I cannot garantuee that this here really works in all cases - this
 seems to be the most stupid file format I've ever seen!
 24 bits integers, time constants instead of Sampling frequencies,
 a lot of needless chunk types...}
TYPE
  tvocheader = RECORD
                 kennstr    : ARRAY [0..$13] OF
                 CHAR;
                 datastart  : WORD;
                 version    : WORD;
               END;

  tvocchunk = RECORD
                blocktype  : BYTE;
                blocksize  : ARRAY [0..2] OF
                BYTE; {really stupid! 24 bits integers!!!}
              END;

  tchunk1 = RECORD     {preceded by chunktype 8 if any other attributes
                        otherwise the data is mono}
              timeconst  : BYTE; {really crappy way to save samplingrate...}
              packmethod : BYTE; {0:8bit; 1:4bit; 2:3bit;3:4bit}
            END;

  tchunk8 = RECORD
              timeconst  : WORD;
              packmethod : BYTE;
              stereo     : BOOLEAN;
            END;

  tchunk9 = RECORD
              frequency  : LONGINT;
              resolution : BYTE;
              channels   : BYTE;
              format     : WORD; {0: 8bit unsigned;4:16bit signed}
              reserved   : ARRAY [0..3] OF
              BYTE;
            END;

VAR
  vochdr    : tvocheader;
  chunk     : tvocchunk;
  chunk1    : tchunk1;
  chunk8    : tchunk8;
  chunk9    : tchunk9;
  blocksize : LONGINT;

  FUNCTION checkchunks : BOOLEAN;
  VAR
    i        : INTEGER;
  BEGIN
    i := 0;
    checkchunks := FALSE;
    {$I-}
    REPEAT
      BLOCKREAD (play.data [datanum] .f, chunk, SIZEOF (chunk) );
      blocksize := LONGINT (chunk.blocksize [2]) SHL 16 +
      LONGINT (chunk.blocksize [1]) SHL 8 +
      LONGINT (chunk.blocksize [0]);
      INC (i);
      CASE chunk.blocktype OF
           1 : BEGIN
               BLOCKREAD (play.data [datanum] .f, chunk1, SIZEOF (chunk1) );
               play.data [datanum] .stereo := FALSE;
               play.data [datanum] .sound16bit := FALSE;
               play.data [datanum] .frequency :=
               256000000 DIV (65536 - (WORD (chunk1.timeconst) SHL 8) );
               play.data [datanum] .fdatasize  := blocksize - SIZEOF (chunk1);
               IF (chunk1.packmethod <> 0) THEN
                  EXIT;{ no packing supported }
               END;
           8 : BEGIN
               BLOCKREAD (play.data [datanum] .f, chunk8, SIZEOF (chunk8) );
               play.data [datanum] .stereo := chunk8.stereo;
               play.data [datanum] .sound16bit := FALSE;
               play.data [datanum] .frequency :=
               256000000 DIV (65536 - ( (WORD (chunk8.stereo) + 1) * chunk8.timeconst) );
               play.data [datanum] .fdatasize  := blocksize - SIZEOF (chunk8);
               IF (chunk8.packmethod <> 0) THEN
                  EXIT;{ no packing supported }
               END;
           9 : BEGIN
               BLOCKREAD (play.data [datanum] .f, chunk9, SIZEOF (chunk9) );
               play.data [datanum] .stereo     := BOOLEAN (chunk9.channels - 1);
               CASE chunk9.format OF
                    0 : play.data [datanum] .sound16bit := FALSE;
                    4 : play.data [datanum] .sound16bit := TRUE;
               ELSE
                    EXIT; { no packing supported }
               END;
               play.data [datanum] .frequency  := chunk9.frequency;
               play.data [datanum] .fdatasize  := blocksize - SIZEOF (chunk9);
               END;
      ELSE
           SEEK (play.data [datanum] .f, FILEPOS (play.data [datanum] .f) + blocksize)
      END;
    UNTIL ( (chunk.blocktype = 1) OR (chunk.blocktype = 8) OR (chunk.blocktype = 9) ) AND
          (blocksize > 12) OR (EOF (play.data [datanum] .f) ) OR (i >= 32);
    IF i >= 32 THEN
       EXIT;
    IF EOF (play.data [datanum] .f) THEN
       EXIT;
    {$I+}
    checkchunks := TRUE;
  END;

BEGIN
  openvoc := sb_filenotfound;
  IF NOT play.data [datanum] .fclosed THEN
     closesound (datanum);
  IF NOT blaster.available THEN
     BEGIN
     openvoc := sb_nocardfound;
     EXIT;
     END;
  IF datanum > 19 THEN
     BEGIN
     openvoc := sb_nohandles;
     EXIT;
     END;

  ASSIGN (play.data [datanum] .f, filename);
  lastfilemode := filemode;
  filemode := 64;
  {$I-}RESET (play.data [datanum] .f, 1);{$I+}

  dummy := IORESULT;
  filemode := lastfilemode;
  IF (dummy <> 0) AND (dummy <> 100) THEN
     EXIT;

  openvoc := sb_falseformat;
  BLOCKREAD (play.data [datanum] .f, vochdr, SIZEOF (vochdr) );
  IF vochdr.kennstr <> 'Creative Voice File'#26 THEN
     BEGIN
     CLOSE (play.data [datanum] .f);
     EXIT;
     END;
  SEEK (play.data [datanum] .f, vochdr.datastart);
  IF NOT checkchunks THEN
     EXIT;
  play.data [datanum] .fdatastart := FILEPOS (play.data [datanum] .f);
  play.data [datanum] .fsize      := FILESIZE (play.data [datanum] .f);

  play.data [datanum] .fileremain := play.data [datanum] .fdatasize;

  play.data [datanum] .fclosed := FALSE;
  openvoc      := sb_noerror;
END;



FUNCTION openwav (datanum : BYTE;
                  filename : STRING) : BYTE;
TYPE
  twavehdr = RECORD {Header of a wavefile}
               formatlength  : LONGINT;
               formattag     : WORD;
               channels      : WORD;
               frequency     : LONGINT;
               bytespersecnd : LONGINT;
               blkalign      : WORD;
               resolution    : WORD;
             END;

  triff = RECORD{20}
            riff      : ARRAY [0..3] OF
            CHAR;
            chunksize : LONGINT;
            acon      : ARRAY [0..3] OF
            CHAR;
          END;

  tlist = RECORD
            list : ARRAY [0..3] OF
            CHAR;
            size : LONGINT;
          END;

VAR
  wavehdr  : twavehdr;
  h        : triff;
  l        : tlist;
  s        : STRING;
  oldpos   : LONGINT;

  FUNCTION checkchunks : BOOLEAN;
  VAR
    i        : INTEGER;
  BEGIN
    i := 0;
    checkchunks := FALSE;
    {$I-}
    BLOCKREAD (play.data [datanum] .f, h, SIZEOF (h) );
    REPEAT
      BLOCKREAD (play.data [datanum] .f, l, SIZEOF (l) );
      IF l.list = 'fmt ' THEN
         BEGIN
         oldpos := FILEPOS (play.data [datanum] .f);
         SEEK (play.data [datanum] .f, oldpos - 4);
         BLOCKREAD (play.data [datanum] .f, wavehdr, SIZEOF (wavehdr) );
         SEEK (play.data [datanum] .f, oldpos + l.size);
         END
      ELSE
      IF l.list <> 'data' THEN
         SEEK (play.data [datanum] .f, FILEPOS (play.data [datanum] .f) + l.size);
      INC (i);
    UNTIL (l.list = 'data') OR (EOF (play.data [datanum] .f) ) OR (i >= 32);
    IF i >= 32 THEN
       EXIT;
    IF EOF (play.data [datanum] .f) THEN
       EXIT;
    {$I+}
    checkchunks := TRUE;
  END;

BEGIN
  openwav := sb_filenotfound;
  IF NOT play.data [datanum] .fclosed THEN
     closesound (datanum);
  IF NOT blaster.available THEN
     BEGIN
     openwav := sb_nocardfound;
     EXIT;
     END;
  IF datanum > 19 THEN
     BEGIN
     openwav := sb_nohandles;
     EXIT;
     END;
  ASSIGN (play.data [datanum] .f, filename);
  lastfilemode := filemode;
  filemode := 64;
  {$I-}RESET (play.data [datanum] .f, 1);{$I+}
  dummy := IORESULT;
  filemode := lastfilemode;
  IF (dummy <> 0) AND (dummy <> 100) THEN
     EXIT;
  IF NOT checkchunks THEN
     BEGIN
     openwav := sb_falseformat;
     EXIT;
     END;
  play.data [datanum] .fdatastart := FILEPOS (play.data [datanum] .f);
  IF wavehdr.formattag <> 1 THEN
     BEGIN {compressed file or unknown sampletype}
     openwav := sb_nocompressed;
     EXIT;
     END;

  IF (wavehdr.resolution <> 8) AND (wavehdr.resolution <> 16) THEN
     BEGIN
     CLOSE (play.data [datanum] .f);
     openwav := sb_falseformat;
     EXIT;
     END;
  BYTE (play.data [datanum] .sound16bit) := wavehdr.resolution DIV 16;
  play.data [datanum] .signed           := play.data [datanum] .sound16bit;
  BYTE (play.data [datanum] .stereo)     := wavehdr.bytespersecnd DIV
  wavehdr.frequency DIV SUCC (BYTE (play.data [datanum] .sound16bit) ) - 1;
  play.data [datanum] .frequency        := wavehdr.frequency;

  play.data [datanum] .fsize := FILESIZE (play.data [datanum] .f);
  play.data [datanum] .fdatasize := {wavehdr.chunklength}l.size;
  play.data [datanum] .fileremain := play.data [datanum] .fdatasize;

  play.data [datanum] .fclosed := FALSE;
  openwav                    := sb_noerror;
END;


FUNCTION opensound (datanum : BYTE;
                    s : STRING) : BYTE;
VAR
  i : BYTE;
BEGIN
  FOR i := 1 TO LENGTH (s) DO
      s [i] := UPCASE (s [i]);
  IF POS ('.VOC', s) <> 0 THEN
     opensound := openvoc (datanum, s)
  ELSE
     opensound := openwav (datanum, s);
END;

PROCEDURE closesound (datanum : BYTE);
BEGIN
  IF NOT blaster.available THEN
     EXIT;
  exitplay;
  {$I-}
  IF NOT play.data [datanum] .fclosed THEN
     CLOSE (play.data [datanum] .f);
  {$I+}
  dummy := IORESULT;
  play.data [datanum] .fclosed := TRUE;
END;

BEGIN
  {$IFNDEF DPMI}
  GETMEM (play.p, buffersize);
  {$ELSE}
  {  globaldosfree(play.p);}
  play.p := globaldosalloc (buffersize);
  {$ENDIF}
  GETMEM (dsbuf, buffersize * 4);
  blaster.available        := FALSE;
  oldexitproc              := exitproc;
  exitproc                 := @exitblaster;
  play.callproc            := dummycaller;
  play.stopped             := TRUE;
  FOR dummy := 0 TO 19 DO
      play.data [dummy] .fclosed := TRUE;
  rec.callproc             := dummycaller;
  rec.stopped              := TRUE;
  rec.fclosed              := TRUE;
  detectblaster            := detectblaster_norm;
END.
{
Filemodes
 0  Read only
 1  Write only
 2  Read/Write
 Deny_all =         $10;
 Deny_write =       $20;
 Deny_read =        $30;
 Deny_none =        $40;
 Inheritance_flag = $80;
}
