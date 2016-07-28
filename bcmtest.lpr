program testbcm;

uses
  cmem,
  {$IFDEF UNIX}{$IFDEF UseCThreads}
  cthreads,
  {$ENDIF}{$ENDIF}

  sysutils,
  classes,
  math,


  bcm;

//////////////////////////// main ////////////////////////////
var
  start: double;

  dmc: tblzstream;

  filesize: int64;

  rs: tmystream;
  ws: tmystream;

begin

  if (paramcount <> 3) then halt;

  if (paramstr(1) = 'c') and (paramcount <> 3) then halt;
  if (paramstr(1) = 'd') and (paramcount <> 3) then halt;

  // start timer
  start := now;
  writeln('gulp v 0.1 an dmc file compressor, (c) 2014');
  writeln('by melchiorre caruso (italy)');

  // open files
  if (paramstr(1) = 'c') then
  begin
    rs := tmystream.create(paramstr(2), false);
    ws := tmystream.create(paramstr(3),  true);
  end else
  begin
    rs := tmystream.create(paramstr(2), false);
    ws := tmystream.create(paramstr(3),  true);
  end;

  // compress
  if (paramstr(1) = 'c') then
  begin
    filesize := getfilesize(paramstr(2));

    ws.write64(filesize);

    dmc := tblzcompressionstream.create(ws);
    while filesize > 0 do
    begin
      dmc.write(rs.read);
      dec(filesize);
    end;

    dmc.destroy;
    ws.destroy;
    rs.destroy;
  end else
  begin // decompress

    filesize := rs.read64;

    dmc := tblzdecompressionstream.create(rs);
    while filesize > 0 do
    begin
      ws.write(dmc.read);
      dec(filesize);
    end;
    dmc.destroy;
    ws.destroy;
    rs.destroy;
  end;

  // print results
  if (paramstr(1) = 'c') then
  begin
    writeln(format('%s (%d bytes) compress to %s (%d bytes) in %1.2f s.',
    [paramstr(2), getfilesize(paramstr(2)), paramstr(3), getfilesize(paramstr(3)),
      (now - start) * (24 * 60 * 60)]));
  end else
  begin
    writeln(format('%s (%d bytes) decompress to %s (%d bytes) in %1.2f s.',
    [paramstr(2), getfilesize(paramstr(2)), paramstr(3), getfilesize(paramstr(3)),
      (now - start) * (24 * 60 * 60)]));
  end;
  writeln;
end.



