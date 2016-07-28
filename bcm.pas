{ Description: BCM compression library.

  Copyright (C) 2014-2016 Melchiorre Caruso <melchiorrecaruso@gmail.com>

  This source is free software; you can redistribute it and/or modify it under
  the terms of the GNU General Public License as published by the Free
  Software Foundation; either version 2 of the License, or (at your option)
  any later version.

  This code is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
  FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
  details.

  A copy of the GNU General Public License is available on the World Wide Web
  at <http://www.gnu.org/copyleft/gpl.html>. You can also obtain it by writing
  to the Free Software Foundation, Inc., 59 Temple Place - Suite 330, Boston,
  MA 02111-1307, USA.
}

unit bcm;

{$mode objfpc}
{$H+}

interface

uses
  classes;

/////////////////////////////// tbcmcoder //////////////////////////////////////

type
  tbcmcoder = class
  private
    stream: tstream;
    code: longword;
    low:  longword;
    high: longword;
  public
    constructor create(s: tstream);
    destructor  destroy; override;
    procedure   flush;
    procedure   init;
    procedure   encode(p: longword; const bit: byte);
    procedure   decode(p: longword; var   bit: byte);
  end;

/////////////////////////////// tbcmcounter ////////////////////////////////////

type
  tbcmcounter = class
  private
    p: longword;
    r: longword;
  public
    constructor create(rate: longword);
    procedure   update(bit: byte);
  end;

/////////////////////////////// tbcmmix ////////////////////////////////////////

type
  tbcmmixer = class(tbcmcoder)
  private
    counter0: array [0..255] of tbcmcounter;
    counter1: array [0..255, 0..255] of tbcmcounter;
    counter2: array [0..1, 0..255, 0..16] of tbcmcounter;
    c1:  longword;
    c2:  longword;
    run: longword;
  public
    constructor create(s: tstream);
    destructor  destroy; override;
    procedure   put(c: longword);
    function    get: longword;
  end;

/////////////////////////////// tbcmstream /////////////////////////////////////

type
  tbcmstream = class
  private
    fbuf: array of byte;
    fbufindex: longword;
    fbufsize:  longword;
    fmixer:    tbcmmixer;
  public
    constructor create(s: tstream);
    destructor  destroy; override;
    procedure   read (var   buffer; count: longint); virtual; abstract;
    procedure   write(const buffer; count: longint); virtual; abstract;
    procedure   flush; virtual; abstract;
    procedure   fill;  virtual; abstract;
  end;

  tbcmcompressionstream = class(tbcmstream)
  public
    constructor create(s: tstream; blocksize: longword);
    destructor  destroy; override;
    procedure   flush; override;
    procedure   write(const buffer; count: longint); override;
  end;

  tbcmdecompressionstream = class(tbcmstream)
  public
    constructor create(s: tstream);
    destructor  destroy; override;
    procedure   fill; override;
    procedure   read (var buffer; count: longint); override;
  end;

implementation

{$ifdef mswindows}
  {$linklib libmsvcrt}
{$endif}

{$ifdef unix}
  {$linklib libc}
  {$linklib libm}
{$endif}

{$ifdef mac}
  todo...
{$endif}

{$link divsufsort.o}

function divsufsort(t: pbyte;           sa: plongint; n: longint): longint; cdecl; external;
function divbwt    (t: pbyte; u: pbyte;  a: plongint; n: longint): longint; cdecl; external;

/////////////////////////////// tbcmcoder //////////////////////////////////////

constructor tbcmcoder.create(s: tstream);
begin
  inherited create;
  stream := s;
  code   := 0;
  low    := 0;
  high   := longword(-1);
end;

destructor tbcmcoder.destroy;
begin
  inherited destroy;
end;

procedure tbcmcoder.flush;
var
  i : longword;
begin
  for i := 0 to 3 do
  begin
    stream.writebyte(low shr 24);
    low := low shl 8;
  end;
end;

procedure tbcmcoder.init;
var
  i : longword;
begin
  for i := 0 to 3 do
    code := (code shl 8) or stream.readbyte;
end;

procedure tbcmcoder.encode(p: longword; const bit: byte);
var
  mid : longword;
begin
  mid := low + ((qword(high - low) * (p shl 14)) shr 32);

  if boolean(bit) then
    high := mid
  else
    low  := mid + 1;

  while ((low xor high) < (1 shl 24)) do
  begin
    stream.writebyte(low shr 24);
    low  := (low  shl 8);
    high := (high shl 8) or $ff;
  end;
end;

procedure tbcmcoder.decode(p: longword; var bit: byte);
var
  mid : longword;
begin
  mid := low + ((qword(high - low) * (p shl 14)) shr 32);

  bit := byte(code <= mid);
  if boolean(bit) then
    high := mid
  else
    low  := mid + 1;

  while ((low xor high) < (1 shl 24)) do
  begin
    code := (code shl 8) or stream.readbyte;
    low  := (low  shl 8);
    high := (high shl 8) or $ff;
  end;
end;

/////////////////////////////// tbcmcounter ////////////////////////////////////

constructor tbcmcounter.create(rate: longword);
begin
  inherited create;
  p := 1 shl 15;
  r := rate;
end;

procedure tbcmcounter.update(bit: byte);
begin
  if boolean(bit) then
    p := p + ((p xor $ffff) shr r)
  else
    p := p - (p shr r);
end;

/////////////////////////////// tbcmmix ////////////////////////////////////////

constructor tbcmmixer.create(s: tstream);
var
  i, j, k : longword;
begin
  inherited create(s);
  c1  := 0;
  c2  := 0;
  run := 0;
  for i := 0 to 255 do
    counter0[i] := tbcmcounter.create(2);
  for i := 0 to 255 do
    for j := 0 to 255 do
      counter1[i, j] := tbcmcounter.create(4);
  for i := 0 to 1 do
    for j := 0 to 255 do
      for k := 0 to 16 do
      begin
        counter2[i, j, k]   := tbcmcounter.create(6);
        counter2[i, j, k].p := (k - longword(k = 16)) shl 12;
      end;
end;

destructor tbcmmixer.destroy;
var
  i, j, k : longword;
begin
  for i := 0 to 255 do
    counter0[i].destroy;
  for i := 0 to 255 do
    for j := 0 to 255 do
      counter1[i, j].destroy;
  for i := 0 to 1 do
    for j := 0 to 255 do
      for k := 0 to 16 do
        counter2[i, j, k].destroy;
  inherited destroy;
end;

procedure tbcmmixer.put(c: longword);
var
  bit: byte;
  ctx: longword;
  f: longword;
  idx: longword;
  p0, p1, p2, p: longword;
  ssep: longword;
  x1, x2: longword;
begin
  if (c1 = c2) then
    inc(run)
  else
    run := 0;

  f   := longword(run > 2);
  ctx := 1;
  while (ctx < 256) do
  begin
    p0   := counter0[ctx].p;
    p1   := counter1[c1][ctx].p;
    p2   := counter1[c2][ctx].p;
    p    := (p0 + p0 + p0 + p0 + p1 + p1 + p1 + p2) shr 3;

    idx  := p shr 12;
    x1   := counter2[f][ctx][idx].p;
    x2   := counter2[f][ctx][idx+1].p;
    ssep := x1 + (((x2 - x1) * (p and $fff)) shr 12);

    bit := longword((c and $80) <> 0);
    inc(c, c);

    encode(p + ssep + ssep + ssep, bit);

    counter0[ctx].update(bit);
    counter1[c1][ctx].update(bit);
    counter2[f][ctx][idx].update(bit);
    counter2[f][ctx][idx + 1].update(bit);

    inc(ctx, ctx + bit);
  end;
  c2 := c1;
  c1 := byte(ctx);
end;

function tbcmmixer.get: longword;
var
  bit: byte;
  ctx: longword;
  f: longword;
  idx: longword;
  p0, p1, p2, p: longword;
  ssep: longword;
  x1, x2: longword;
begin
  if (c1 = c2) then
    inc(run)
  else
    run := 0;

  f   := longword(run > 2);
  ctx := 1;
  while (ctx < 256) do
  begin
    p0   := counter0[ctx].p;
    p1   := counter1[c1][ctx].p;
    p2   := counter1[c2][ctx].p;
    p    := (p0 + p0 + p0 + p0 + p1 + p1 + p1 + p2) shr 3;

    idx  := p shr 12;
    x1   := counter2[f][ctx][idx].p;
    x2   := counter2[f][ctx][idx + 1].p;
    ssep := x1 + (((x2 - x1) * (p and $fff)) shr 12);

    decode(p + ssep + ssep + ssep, bit);

    counter0[ctx].update(bit);
    counter1[c1][ctx].update(bit);
    counter2[f][ctx][idx].update(bit);
    counter2[f][ctx][idx + 1].update(bit);

    inc(ctx, ctx + bit);
  end;
  c2 := c1;
  c1 := byte(ctx);
  result := c1;
end;

/////////////////////////////// tbcmstream /////////////////////////////////////

constructor tbcmstream.create(s: tstream);
begin
  inherited create;
  fmixer := tbcmmixer.create(s);
end;

destructor  tbcmstream.destroy;
begin
  fmixer.destroy;
  inherited destroy;
end;

constructor tbcmcompressionstream.create(s: tstream; blocksize: longword);
begin
  inherited create(s);
  fbufindex := 0;
  fbufsize  := blocksize;
  setlength(fbuf, fbufsize);
end;

destructor tbcmcompressionstream.destroy;
begin
  flush;
  fmixer.put(0);
  fmixer.put(0);
  fmixer.put(0);
  fmixer.put(0);
  fmixer.flush;
  setlength(fbuf, 0);
  inherited destroy;
end;

procedure tbcmcompressionstream.write(const buffer; count: longint);
var
  bytes: array [0..$FFFFFFF] of byte absolute buffer;
  i: longint;
begin
  for i := 0 to count - 1 do
  begin
    if fbufindex = fbufsize then flush;
    fbuf[fbufindex] := bytes[i];
    inc(fbufindex);
  end;
end;

procedure tbcmcompressionstream.flush;
var
  i     : longword;
  index : longword;
begin
  if fbufindex <> 0 then
  begin
    index := divbwt(@fbuf[0], @fbuf[0], nil, fbufindex);

    writeln('buffer = ', fbufindex, ' | index = ', index);

    fmixer.put(fbufindex shr 24);
    fmixer.put(fbufindex shr 16);
    fmixer.put(fbufindex shr  8);
    fmixer.put(fbufindex);

    fmixer.put(index shr 24);
    fmixer.put(index shr 16);
    fmixer.put(index shr  8);
    fmixer.put(index);

    for i := 0 to fbufindex - 1 do
      fmixer.put(fbuf[i]);
    fbufindex := 0;
  end;
end;

constructor tbcmdecompressionstream.create(s: tstream);
begin
  inherited create(s);
  setlength(fbuf, 0);
  fbufsize  := 0;
  fbufindex := 0;
  fmixer.init;
end;

destructor tbcmdecompressionstream.destroy;
begin
  setlength(fbuf, 0);
  inherited destroy;
end;

procedure tbcmdecompressionstream.read(var buffer; count: longint);
var
  bytes: array [0..$FFFFFFF] of byte absolute buffer;
  i: longint;
begin
  for i := 0 to count - 1 do
  begin
    if fbufsize = fbufsize then fill;
    bytes[i] := fbuf[fbufindex];
    inc(fbufindex);
  end;
end;

procedure tbcmdecompressionstream.fill;
var
  i: longint;
  index: longword;
  t: array[0..256] of longint;
  next: plongint;
begin
  fbufsize := (fmixer.get shr 24) or
              (fmixer.get shr 16) or
              (fmixer.get shr  8) or
              (fmixer.get);
  setlength(fbuf, fbufsize);

  index := (fmixer.get shr 24) or
           (fmixer.get shr 16) or
           (fmixer.get shr  8) or
           (fmixer.get);

  fillchar(t, sizeof(t), 0);
  for i := 0 to fbufsize - 1 do
  begin
    fbuf[i] := fmixer.get;
    inc(t[fbuf[i] + 1]);
  end;

  for i := 1 to 255 do
    t[i] := t[i] + t[i - 1];

  next := @fbuf[fbufsize];
  for i := 0 to fbufsize - 1 do
    next[t[fbuf[i]]] := i + longint(i >= index);

  i := index;
  while i <> 0 do
  begin
    i := next[i - 1];
    fbuffer[i - (i>= index)] :=


  end;



end;

end.

