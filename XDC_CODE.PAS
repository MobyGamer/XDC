unit xdc_codegeneration;
{
Contains all structures and procedures responsible for generating code.
}

interface

uses
  xdc_deltas;

type
  codeGenType=(size,speed);
  {size = default, for 8088.  Generate smallest deltas possible.
  speed = enforces faster code for 8086 platforms at the expense of size}

const
  codeGenMax=10; {in bytes}
  optimizeCode:codeGenType=size;
  (* DRAM refresh enabled: *)
  REPMOVSWcycleCost=38.4; {one iteration of REP MOVSW}
  REPSTOSWcycleCost=27.4; {one iteration of REP STOSW}
  lastAL:word=0; {we can cache AX because our runs are sorted by value}
  ALcached:boolean=false;

  frameHeaderLen=14;
  frameHeaderCode:array[0..frameHeaderLen-1] of byte=(
    $1E,             {PUSH    DS     }
    $0E,             {PUSH    CS     }
    $1F,             {POP     DS     }
    $BE,$FF,$FF,     {MOV     SI,FFFF}
    $B8,$00,$B8,     {MOV     AX,B800}
    $8E,$C0,         {MOV     ES,AX  }
    $B5,$00,         {MOV     CH,00  }
    $FC              {CLD            }
  );
  frameHeaderCycles=18*4;

  frameFooterLen=2;
  frameFooterCode:array[0..frameFooterLen-1] of byte=(
    $1F,             {POP     DS     }
    $CB              {RETF           }
  );
  frameFooterCycles=(3*4)+34;

  frameByteOverhead=frameHeaderLen+frameFooterLen;
  frameCycleOverhead=frameHeaderCycles+frameFooterCycles;



type
  opcodetype=record
    ob:byte; {opcode byte}
    oc:real; {total cycle time (higher value of (IOs*4) vs. execution time}
  end;

  opcodeList=(
    pushDS,
    pushCS,
    popDS,
    movSI,
    movAX,
    movESAX1,
    movESAX2,
    cld,
    movAL,
    movCL,
    movCX,
    movDI,
    repz,
    movsb,
    movsw,
    stosb,
    stosw,
    retf,
    es,
    movbpmem1,
    movbpmem2,
    movwpmem1,
    movwpmem2
  );

  opcodesType=array[opcodeList] of opcodeType;

  {Data structure to hold output of delta compilation step for later linking.
  "Values" are stored on the stack and, as such, must be word-aligned.}
  PEncodeTarget=^TEncodeTarget;
  TEncodeTarget=record
    codes:array[0..codeGenMax-1] of byte;
    numOpcodeBytes:word;
    numDataBytes:word;
    totalBytes:word;
    totalCycles:real; {in cycles, represents TOTAL execution time}
    modifiedAL:boolean;
    AL:word;
  end;

procedure encodeDelta(d:pdelta; var enc:TEncodeTarget);

implementation

uses
  xdc_globals,xdc_common;

const
  {Order MUST match that of opcodeList!}
  opcode:opcodesType=(
    {pushDS}     (ob:$1e; oc:4*3),
    {pushCS}     (ob:$0e; oc:4*3),
    {popDS}      (ob:$1f; oc:4*3),
    {movSI}      (ob:$be; oc:4*3),
    {movAX}      (ob:$b8; oc:4*3),
    {movESAX1}   (ob:$8e; oc:4),
    {movESAX2}   (ob:$c0; oc:4),
    {cld}        (ob:$fc; oc:4),
    {movAL}      (ob:$b0; oc:4*2),
    {movCL}      (ob:$b1; oc:4*2),
    {movCX}      (ob:$b9; oc:4*3),
    {movDI}      (ob:$bf; oc:4*3),
    {repz}       (ob:$f3; oc:4),
    {movsb}      (ob:$a4; oc:4+(REPMOVSWcycleCost / 2)),
    {movsw}      (ob:$a5; oc:4+REPMOVSWcycleCost),
    {stosb}      (ob:$aa; oc:4+(REPSTOSWcycleCost / 2)),
    {stosw}      (ob:$ab; oc:4+REPSTOSWcycleCost),
    {retf}       (ob:$cb; oc:4),
    {es}         (ob:$26; oc:4),
    {movbpmem1}  (ob:$c6; oc:0),   {total cycles in next part}
    {movbpmem2}  (ob:$06; oc:4*6), {2 opcode bytes, 3 operand bytes, 1 store}
    {movwpmem1}  (ob:$c7; oc:0),   {total cycles in next part}
    {movwpmem2}  (ob:$06; oc:4*8)  {2 opcode bytes, 4 operand bytes, 2 store}
  );

procedure encodeDelta(d:pdelta; var enc:TEncodeTarget);
{Encode to multiple targets; pick best target based on user preference.
We will use this not just
in the encode step, but in the delta optimization step that comes before
actual encoding.}

const
  maxUnroll=6;

var
  encodes:array[0..4] of TEncodeTarget;
  b,numEnc:byte;
  opcodepos:byte;

  procedure injectOpcode(o:opcodeList);
  begin
    encodes[numEnc].codes[opcodepos]:=opcode[o].ob;
    inc(opcodePos);
    inc(encodes[numEnc].numOpcodeBytes);
    encodes[numEnc].totalCycles:=encodes[numEnc].totalCycles+opcode[o].oc;
  end;

  procedure injectWordval(w:word);
  begin
    encodes[numEnc].codes[opcodepos  ]:=lo(w);
    encodes[numEnc].codes[opcodepos+1]:=hi(w);
    inc(opcodePos,2);
    inc(encodes[numEnc].numOpcodeBytes,2);
  end;

  procedure injectByteval(b:byte);
  begin
    encodes[numEnc].codes[opcodepos]:=b;
    inc(opcodePos);
    inc(encodes[numEnc].numOpcodeBytes);
  end;

  procedure encodeSTOS;
  var
    loop:byte;
  begin
    opcodepos:=0;
    injectOpcode(movdi); injectWordVal(d^.startofs);
    {if AL not cached, set new one}
    if (lastAL<>d^.fillvalue) or not ALcached then begin
      injectOpcode(moval); injectbyteVal(d^.fillvalue); ALcached:=true;
      encodes[numEnc].AL:=d^.fillValue;
      encodes[numEnc].modifiedAL:=true;
    end;
    {inject STOSBs}
    for loop:=0 to d^.blength-1 do injectOpcode(stosb);
    with encodes[numEnc] do totalbytes:=numOpcodeBytes+numDataBytes;
    inc(numEnc);
  end;

  procedure encodeMOVS;
  begin
    opcodepos:=0;
    injectOpcode(movdi); injectWordVal(d^.startofs);
    case d^.blength of
      1:begin
        injectOpcode(movsb);
      end;
      2:begin
        injectOpcode(movsw);
      end;
      3:begin
        injectOpcode(movsw);
        injectOpcode(movsb);
      end;
      4:begin
        injectOpcode(movsw);
        injectOpcode(movsw);
      end;
      5:begin
        injectOpcode(movsw);
        injectOpcode(movsw);
        injectOpcode(movsb);
      end;
      6:begin
        injectOpcode(movsw);
        injectOpcode(movsw);
        injectOpcode(movsw);
      end;
    else
      fatalerr('cannot unroll MOVS beyond max unroll length');
    end;
    encodes[numEnc].numDataBytes:=d^.blength;
    with encodes[numEnc] do totalbytes:=numOpcodeBytes+numDataBytes;
    inc(numEnc);
  end;

  procedure encodeREPSTOS;
  begin
    opcodepos:=0;
    injectOpcode(movdi); injectWordVal(d^.startofs);
    if (d^.blength<=255) then begin
      injectOpcode(movcl);
      injectByteVal(d^.blength);
    end else begin
      injectOpcode(movcx);
      injectWordVal(d^.blength);
    end;
    if (lastAL<>d^.fillvalue) or not ALcached then begin
      injectOpcode(moval); injectbyteVal(d^.fillvalue); ALcached:=true;
      encodes[numEnc].AL:=d^.fillValue;
      encodes[numEnc].modifiedAL:=true;
    end;
    injectOpcode(repz);
    injectOpcode(stosb);
    encodes[numEnc].totalCycles:=
      encodes[numEnc].totalCycles+(d^.blength*(REPSTOSWcycleCost/2));
    with encodes[numEnc] do totalbytes:=numOpcodeBytes+numDataBytes;
    inc(numEnc);
  end;

  procedure encodeREPMOVS;
  begin
    opcodepos:=0;
    injectOpcode(movdi); injectWordVal(d^.startofs);
    if (d^.blength<=255) then begin
      injectOpcode(movcl);
      injectByteVal(d^.blength);
    end else begin
      injectOpcode(movcx);
      injectWordVal(d^.blength);
    end;
    injectOpcode(repz);
    injectOpcode(movsb);
    encodes[numEnc].totalCycles:=
      encodes[numEnc].totalCycles+(d^.blength*(REPMOVSWcycleCost/2));
    encodes[numEnc].numDataBytes:=d^.blength;
    with encodes[numEnc] do totalbytes:=numOpcodeBytes+numDataBytes;
    inc(numEnc);
  end;

  procedure encodeMOV;
  var
    loop:byte;
    pb:^byte;
    pw:^word;
  begin
    opcodepos:=0;
    case d^.blength of
      1:begin
        injectOpcode(es);
        injectOpcode(movbpmem1);
        injectOpcode(movbpmem2);
        injectWordVal(d^.startofs);
        pb:=prevframe;
        word(pb):=d^.startofs;
        injectByteVal(pb^);
      end;
      2:begin
        injectOpcode(es);
        injectOpcode(movwpmem1);
        injectOpcode(movwpmem2);
        injectWordVal(d^.startofs);
        pw:=prevframe;
        word(pw):=d^.startofs;
        injectWordVal(pw^);
      end;
    else
      fatalerr('no dword pointer on this architecture');
    end;
    with encodes[numEnc] do totalbytes:=numOpcodeBytes+numDataBytes;
    inc(numEnc);
  end;

begin
  fillchar(Enc,sizeof(Enc),$ff);
  fillchar(encodes,sizeof(encodes),0);
  for b:=0 to 4 do encodes[b].modifiedAL:=false;
  enc.numOpcodeBytes:=maxVChunk;
  enc.numDataBytes:=maxVChunk;
  enc.totalBytes:=maxVChunk*2;
  enc.totalCycles:=totalCyclesPerFrame;
  enc.modifiedAL:=false;
  numEnc:=0;

  {encode in every way that makes sense}
  if d^.dtype=run then begin
    if d^.blength<=maxUnroll then encodeSTOS;
    encodeREPSTOS;
  end;
  if d^.blength<=maxUnroll then encodeMOVS;
  encodeREPMOVS;
  if d^.blength < 3 then encodeMOV;

  {pick the best encode for our user preferences: size or speed}
  for b:=0 to numEnc-1 do begin
    if optimizeCode=size then begin
      if (encodes[b].totalBytes < Enc.totalBytes)
        then Enc:=encodes[b];
    end;
    if optimizeCode=speed then begin
      if (encodes[b].totalCycles < Enc.totalCycles)
        then Enc:=encodes[b];
    end;
  end;
end;


end.