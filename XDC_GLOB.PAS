unit xdc_globals;
{global variables and constants used by the entire framework}

(*

XDC is sufficiently different than the previous attempt that it requires
a new format.  First, a short glossary:

Chunk:  A section of video data or audio data.
        There are video chunks and audio chunks.

Packet: A section of audio+video data.

Here is the XDC muxed stream format (known as an "XDV" stream or "XDV" file).
It begins with a header:

'XDCV'     - 4 bytes, header signature
numpackets - 2 bytes, word value, number of packets that follow header
largestpacket - 2 byte, word value, size in bytes of largest packet in the file
achunksize - 2 bytes, word value, size of each audio chunk.
             This is always a fixed value even when compressed audio formats
             are in use, because each audio compression method produces
             fixed-size output chunks.
samprate   - 2 bytes, word value, playback sample rate in Hz
vidmode    - 1 byte, 1=160x200x16 composite CGA, 2=640x200x2 (others to follow?)
numbcols   - 1 byte, width of screenmode in byte columns (ie. 80)
numprows   - 1 byte, height of screenmode in pixel rows (ie. 200)
features   - 1 byte, bitfield, reserved for special handling:
padding    - rest of header is padded to the first sector boundary (512)

feature byte, currently unused:
76543210
||||||||
|||||||+--a_compm1     If set, audio data is compressed using method 1 (DPCM)
||||||+---a_compm2     If set, audio data is compressed using method 2 (VQ)
|||||+----a_stereo     If set, audio data is stereo (LRLR)
||||+-----reserved
|||+------reserved
||+-------reserved
|+--------reserved
+---------reserved

After the header, comes one or more audio+video "packets" with the
following structure:

  0..end of videochunk
  ...unknown # of padding...
  audiochunk..end of packet

The very beginning of the packet is the video chunk, which is of a
variable size.  The very end of the packet is the audio chunk, which can
easily be found by seeking backwards from the end "achunksize" bytes.
All packets are aligned to sector boundaries (ie. the nearest 512-byte
boundary).  The data in the packet between the video and audio chunks is
undefined (although likely filled with 0).

Video playback framerate is derived by the audio sample rate divided by the
audio chunk size.  It is possible (in fact, likely) that neither the framerate
or audio sample rate will be a common/expected value.  For example, samplerate
could have been adjusted during creation from 32Khz to 32008Hz to avoid drift,
or the framerate could be a non-integral number like 29.97 or 23.976.

Packets are padded to the nearest sector boundary (512-byte boundary).  At the
end of an XDV stream is an index that stores the size of each packet in
sectors, one value per byte.  (For example: A (tiny) stream that has
numpackets=4 would have, at EOF-4, 4 bytes, one for each packet to read, with
each value multiplied by 512 to get the packet length.)  Loading the index is
as easy as reading [numpackets] from the header and then seeking to
EOF-[numpackets], then reading [numpackets] bytes.  This index must obviously
be loaded prior to playback so that the player knows how much data to load
from disk for each packet.

*)

interface

const
  debug:byte=1;               {debug level, higher values increase verbosity}
  maxbuf=65536-16;
  secsize=512;                {size of a disk sector
                              packets will be padded/aligned to this}

  {set our raw, native frames per second for CGA.  From Andrew Jenner:
  "Normal CGA has 228 color-carrier cycles per scanline instead of 227.5,
  and 262 scanlines per field instead of 262.5"}
  defaultFPS=(60000/1001)*(227.5/228)*(262.5/262);
  sourceFPS:real=defaultFPS;  {framerate of source material}
  encodeFPS:real=defaultFPS;  {rate we are actually generating frames at}
  REPMOVSbyteCost=7;          {mov cl; mov di; rep movs}
  REPSTOSbyteCost=9;          {mov al; mov cl; mov di, rep stos}

  {global constants that can be tweaked by the user that determine the
  type and amount of optimization:}
  shavePixels:boolean=false;  {if true, # of changed pixels in a 1-byte delta
                              must be above a certain threshold}
  shavePixelMinimum:byte=2;   {# of pixels that must be different in a 1-byte
                              delta before it will be retained.  Anything
                              lower will result in it being discarded.}
  pixelBitDepth:byte=1;       {used to determine proper pixel shaving}
  shaveDeltas:boolean=false;  {discard deltas under a certain byte length}
  shaveDeltaMinimum:byte=3;   {# of bytes that must be in a delta for it to
                              be retained.  Anything smaller will be discarded.
                              This is very aggressive and can substantially
                              degrade image quality; consider its use carefully}
  maxDiskRate:word=0;         {maximum disk bitrate to use, in KB}
  blankOnFull:boolean=false;  {if input is changing entire screen and this
                              is TRUE, force encode of a full blank/zero-
                              fill frame so that the mode or palette change
                              is not visible to the user on playback}
  minRunLength:byte=REPSTOSbyteCost;
                              {min. length for run to be encoded as REP STOS.
                              This value is estimated based on 5 or 6 code
                              bytes (popcx,popax,popdi,repstosw,stosb) and
                              6 value bytes (ax,cx,di) for a total of 12}
  combineDeltas:boolean=true; {Combine slices to save code space.  Disable
                              for a speed boost during encoding.}
  maxCombineDistance:byte=REPMOVSbyteCost;
                              {If any slices are this close or closer to each
                              other, consider combining them.  We will either
                              save generatd code space, time, or both.}
  murryHandling:boolean=false;{Try to replay deltas compensating for CGA
                              interlacing artifacts.  If you don't like how
                              CGA interlacing playback looks, enable this.
                              Might look worse enabled when bandwidth starved.}
  cheating:boolean=false;     {If cheating, only every other line is updated.
                              This was a common cheating technique for slow
                              video cards in the 1990s.}

  {
  Maximum cycle counts we cannot exceed based on Andrew Jenner's measurements:
  }
  totalCyclesPerFrame=76*262*4; {total CPU cycles available in 1/60th sec}
  CyclesPerFrame:real=totalCyclesPerFrame / 2;
  {Calibrated for 60Hz output -- we know from experience that sustained 60hz
  playback is not feasible if we exceed this, even with XT-IDE/CF/DMA cards}

  screenmode:byte=0;
{$IFDEF HP95LX}
  screenbytewidth:byte=30;
  screenbyteheight:byte=128;
  screenRAMsize:word=4096;
  maxVChunk:longint=2000;
{$ELSE}
  screenbytewidth:byte=80;
  screenbyteheight:byte=200;
  screenRAMsize:word=16384;   {to account for extra junk between interlaced
                              banks, although can be overridden if I ever
                              decide to support tweakmodes}
  maxVChunk:longint=8000;     {maximum # of bytes to write to disk as a frame}
{$ENDIF}

type
  XDVheader=record
    signature:array[0..3] of char;
    numpackets:word;
    largestPacket:word;
    achunksize:word;
    samplerate:word;
    vidmode:byte;
    numbcols:byte;
    numprows:byte;
    features:byte;
    {above is 16 bytes}
    filler:array[0..secsize-16-1] of byte;
  end;

  TPacketIndex=array[0..maxbuf-1] of byte;
  PPacketIndex=^TPacketIndex;

var
  packetIndex:PPacketIndex;

implementation

end.
