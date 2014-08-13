unit xdc_deltas;
{
Contains all structures and procedures related to managing
the list of changes ("deltas") needed to reconstruct
a new video frame.

More "meta" operations such as estimation and optimization are not included
here; consider this a base class.
}

interface

uses
  objects;

{object-oriented data structure for managing and optimizing deltas}
type
  deltaType=(slice,run); {slice=not all bytes identical; run=all bytes same}

  PDelta=^TDelta;
  TDelta=object(TObject)
    startOfs:word; {starting offset of delta in buffer (first changed byte)}
    endOfs:word; {ending offset of delta in buffer (last changed byte)}

    {these are calculated during insert or other operations:}
    dtype:deltaType; {slice or run}
    fillvalue:byte; {for informational purposes only, not used for anything}
    blength:word; {length of delta in bytes}
    numPixelsChanged:word; {# of pixels changed in the entire delta}
    REPcycleCost:real; {different whether slice or run}
    frozen:boolean; {flag used to control various optimization phases}

    Constructor Init(starto,endo:word);
    Destructor Done; virtual;
  end;

  PDeltas=^TDeltas;
  TDeltas=object(TSortedCollection)
    function Compare(Key1, Key2: Pointer): Integer; virtual;

    {the following used mostly for debugging:}
    function GetSize:word; {returns entire list in raw output bytes}
    function GetCycles:real; {returns entire list in estimated REP cycles}
    (* function GetEncodedBytes:word; {returns entire list in estimated REP cycles} *)
    function DumpAll:word;
    procedure SplitAll; {splits every delta in two; used for error recovery}
  end;

  {This structure used only for temporary management of deltas in the
  "combine" optimization phase}
  PDeltaStarts=^TDeltaStarts;
  TDeltaStarts=object(TDeltas)
    {Must sort by starting offset so that we can navigate geographically-
    close structures efficiently}
    function Compare(Key1, Key2: Pointer): Integer; virtual;
  end;

var
  {frame buffers:}
  nextframe,prevframe,CGARAM:pointer;

function deltaInfo(d:pdelta):string;

implementation

uses
  xdc_globals,xdc_log,xdc_common,xdc_codegeneration,support;

Constructor tdelta.init;
var
  w,loop:word;
  bpn,bpp:^byte;
  b:byte;
begin
  Inherited Init;
  if endo<starto then fatalerr('end offset '+inttostr(endo)+' < start offset '+inttostr(starto)+'?');
  startofs:=starto;
  endofs:=endo;
  blength:=1+(endofs-startofs);
  if blength=0 then fatalerr('blength 0?');
  if blength>screenRAMsize then fatalerr('blength > screen?');
  {determine if what was just submitted is a slice or a run by checking the
  entire delta to see if all bytes equal the first byte}
  if blength<minRunLength
    then dtype:=slice
    else begin
      bpn:=nextFrame;
      word(bpn):=startofs;
      {assume it is a run until discover otherwise}
      dtype:=run;
      b:=bpn^;
      for w:=startofs to endofs do begin
        word(bpn):=w;
        if bpn^<>b then begin
          dtype:=slice;
          break;
        end;
      end;
      {if we are a run, record what value we fill with}
      if dtype=run
        then fillvalue:=b
        else fillvalue:=0;
    end;
  if dtype=run
    then if debug>1
      then stderr('run found: '+inttostr(startofs)+', len: '+inttostr(blength));
  numPixelsChanged:=$FFFF; {dummy impossible value for now}
  frozen:=false;

  {determine the REP MOVSW or REP STOSW cycle cost}
  if dtype=slice
    then REPcycleCost:=(blength*REPMOVSWcycleCost) / 2
    else REPcycleCost:=(blength*REPSTOSWcycleCost) / 2;

  {if delta is one byte long, determine the # of pixels that have changed}
  if blength=1 then begin
    numPixelsChanged:=0;
    bpn:=nextframe;
    bpp:=prevframe;
    inc(word(bpn),startofs);
    inc(word(bpp),startofs);
    b:=bpn^ XOR bpp^;
    if b=0 then begin
      {This "should never happen" but occasionally does due to design of the
      program (decoupled delta optimization phases).
      Fixing this would require re-engineering the entire
      optimization phase, and since this is not a fatal error, it is okay
      to just warn the programmer and keep going.}
      if debug>2 then stderr('Non-empty byte is empty at '+hexword(startofs)
        +' with values '+bytetohex(bpp^)+' and '+bytetohex(bpn^));
      numPixelsChanged:=0;
    end else begin
      case pixelBitDepth of
        1:begin
            for loop:=0 to 7 do begin
              inc(numPixelsChanged,b AND 1);
              b:=b shr 1;
            end;
          end;
        4:begin
            if ((b AND $F0) SHR 4) <> 0 then inc(numPixelsChanged);
            if  (b AND $0F)        <> 0 then inc(numPixelsChanged);
          end;
        8:numPixelsChanged:=1;
      else
        fatalerr('Cannot process pixels for this bit depth (write more code!)');
      end;
    end;
  end;
end;

Destructor TDelta.Done;
begin
  Inherited Done;
end;

Function TDeltas.Compare;
{
We want to maximize motion fidelity, so we are going to make our lives
easier and sort deltas by size.
Note that the comparisons are reversed -- that's because we want the largest
deltas at the beginning of the list.  (-1 means beginning of collection.)
- We add a second comparison so that deltas of the same length are sorted
by cycle execution time; this keeps runs prioritized over slices in terms
of what to prioritize if our bandwidth gets starved.
- We add a third comparison so that runs of the same run value
are kept together, so that we can cache the run value.
- We can optionally add a fourth comparison so that, all things being equal,
deltas are sorted by start offset compensated for CGA interlaced memory layout
(this is what I'm colloquially calling "Dave Murry interlace handling"
based on how Dave handled it in the PC booter Sierra Championship Boxing).
}

var
  k1so,k2so:word;

begin
  k1so:=PDelta(Key1)^.startofs;
  k2so:=PDelta(Key2)^.startofs;
  if MurryHandling then begin
    {if k1so > screenRAMsize div 2 then k1so:=k1so-(screenRAMsize div 2);
    if k2so > screenRAMsize div 2 then k2so:=k2so-(screenRAMsize div 2);}
    k1so:=k1so AND $1fff;
    k2so:=k2so AND $1fff;
  end;
  {sort by delta length}
  if PDelta(Key1)^.blength > PDelta(Key2)^.blength
    then Compare := -1
    else if PDelta(Key1)^.blength < PDelta(Key2)^.blength
      then Compare := 1
      {sort runs at a higher priority than slices}
      else if PDelta(Key1)^.REPcycleCost < PDelta(Key2)^.REPcycleCost
        then Compare := -1
        else if PDelta(Key1)^.REPcycleCost > PDelta(Key2)^.REPcycleCost
          then Compare := 1
          {sort runs by fill value}
          else if PDelta(Key1)^.fillvalue > PDelta(Key2)^.fillvalue
            then Compare := -1
            else if PDelta(Key1)^.fillvalue < PDelta(Key2)^.fillvalue
              then Compare := 1
              {sort deltas by start offset}
              else if k1so < k2so
                then Compare := -1
                else if k1so > k2so
                  then Compare := 1
                  else Compare := 0;
end;

Procedure TDeltas.SplitAll;
{Edge cases exist where the simplest recovery option is to just split
every delta into two parts of equal sizes.  This method does that quickly by
taking advantage of the fact that the list is sorted by size, with largest
at the top.  In a single iteration from the bottom of the list to the top,
each delta is subdivided.  Newer, smaller deltas created by splits are
ignored due to the nature of the foreach counting down.}
var
  w,blen:word;
  dtmp,dsplit1,dsplit2:pDelta;
begin
  for w:=Count-1 downto 0 do begin
    dtmp:=at(w);
    if dtmp^.blength<2 then continue; {can't split a 1-byte delta!}
    blen:=dtmp^.blength div 2;
    dsplit1:=new(pdelta,init(dtmp^.startofs,dtmp^.startofs+blen));
    dsplit2:=new(pdelta,init(dtmp^.startofs+blen+1,dtmp^.endofs));
    insert(dsplit1);
    insert(dsplit2);
    free(dtmp);
  end;
end;

Function TDeltas.GetSize;
{returns total size of all deltas in bytes.  This is for informal use only,
as it doesn't take into account the size of the generated code necessary
to replay these deltas.}
var
  w:word;

  Procedure addsize(d:PDelta); far;
  begin
    inc(w,d^.blength);
  end;

begin
  w:=0;
  ForEach(@addsize);
  GetSize:=w;
end;

Function TDeltas.GetCycles;
{returns total time of all deltas in cycles.  This is for informal use only,
as it doesn't take into account the other execution time of the generated code
necessary to replay these deltas.}
var
  r:real;

  Procedure addCycles(d:PDelta); far;
  begin
    r:=r+d^.REPcycleCost;
  end;

begin
  r:=0;
  ForEach(@addCycles);
  GetCycles:=r;
end;

Function TDeltas.DumpAll;
{writes all deltas to the program log}

  Procedure dumpDelta(d:PDelta); far;
  begin
    if debug>1 then stdout(deltaInfo(d));
  end;

begin
  if debug>2 then stdout('Dumping '+inttostr(count)+' deltas '
    +'(output bytes '+inttostr(getsize)
    +', total cycles '+realtostr(getcycles)+'):');
  ForEach(@dumpDelta);
end;

Function TDeltaStarts.Compare;
{Sort by starting offset in ascending order}

begin
  if PDelta(Key1)^.startofs < PDelta(Key2)^.startofs
    then Compare := -1
    else if PDelta(Key1)^.startofs > PDelta(Key2)^.startofs
      then Compare := 1
      else Compare := 0;
end;

function deltaInfo(d:pdelta):string;
var
  s:string;
begin
  s:=' delta info: ';
  s:=s+hexword(d^.startofs)+'-'+hexword(d^.endofs)+':'+intpadded(d^.blength,5,#32);
  s:=s+' cost: '+realtostr(d^.REPcycleCost);
  if d^.dtype=run then s:=s+', run of '+hex(d^.fillvalue);
  if debug>2 then if d^.blength=1 then s:=s+', # changed pixels '+inttostr(d^.numPixelsChanged);
  if d^.frozen then s:=s+' (FROZEN)';
  deltaInfo:=s;
end;



(*
Function TDeltas.GetEncodedBytes;
{returns total time of all deltas in cycles.  This is for informal use only,
as it doesn't take into account the other execution time of the generated code
necessary to replay these deltas.}
var
  w:word;

  Procedure addEncoded(d:PDelta); far;
  var
    _tmpe:TEncodeTarget;
  begin
    encodeDelta(d,_tmpe);
    inc(w,_tmpe.totalBytes);
  end;

begin
  w:=0;
  ForEach(@addEncoded);
  GetEncodedBytes:=w;
end;
*)


end.