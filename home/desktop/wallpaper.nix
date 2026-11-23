# The wallpaper, drawn from palette.nix: a night sky over mountain ridges
# and rows of pines, rendered to a 4K PNG at build time. Change the palette
# and it follows. The shapes come from fixed seeds, so it's the same picture
# every build.
#
# Everything adjustable is in `settings`. The wallpaper editor (an artifact
# page) draws the same picture live and copies a settings block in exactly
# this shape: paste it over this one.
{ pkgs, lib }:
let
  settings = {
    sky = { horizon = 0.85; stars = 110; starSeed = 11; };   # horizon: how far bg goes toward teal
    moon = { x = 2850; y = 430; r = 64; glow = 330; };
    # Back to front. A colour is { from; to; t; }: t of the way from one
    # palette colour to another (t = 0 is just `from`). "horizon" is the sky
    # colour at the bottom.
    ridges = [
    ];
    pines = [
      { seed = 21; base = 1496; step = 46; lo = 110; hi = 230; roll = 50; width = 0.24; color = { from = "surf"; to = "bg"; t = 0.2; }; }
      { seed = 22; base = 1756; step = 70; lo = 170; hi = 340; roll = 70; width = 0.24; color = { from = "surf"; to = "bg"; t = 0.65; }; }
      { seed = 23; base = 2160; step = 120; lo = 300; hi = 620; roll = 90; width = 0.24; color = { from = "bg"; to = "bg"; t = 0; }; }
    ];
  };

  w = 3840;
  h = 2160;

  # mix "131A16" "25565C" 0.3: 30% of the way from the first colour to the second.
  mix = a: b: t:
    let
      ch = hex: i: lib.fromHexString (builtins.substring i 2 hex);
      one = i: let v = builtins.floor ((ch a i) * (1 - t) + (ch b i) * t + 0.5); s = lib.toHexString v;
               in if v < 16 then "0" + s else s;
    in one 0 + one 2 + one 4;

  p = (import ../../lib/palette.nix).for "wallpaper";
  c = p // { horizon = mix p.bg p.teal settings.sky.horizon; };
  colour = s: mix c.${s.from} c.${s.to} s.t;

  # Pseudo-random numbers in Nix: a seeded LCG, so every build agrees. The
  # editor uses the same one.
  mod = a: b: a - (a / b) * b;
  next = s: mod (s * 1103515245 + 12345) 2147483648;
  # n whole numbers in [lo, hi), from seed.
  randoms = seed: n: lo: hi:
    let go = s: i: if i == n then [ ] else let s' = next s; in [ (lo + mod (s' / 65536) (hi - lo)) ] ++ go s' (i + 1);
    in go seed 0;

  num = x: toString (builtins.floor (x + 0.5));
  pt = x: y: "L${num x} ${num y} ";
  closed = base: body: "M0 ${toString h} L0 ${toString base} ${body}L${toString w} ${toString base} L${toString w} ${toString h} Z";

  # Mountains: a peak every ~step px, nudged sideways, with a shoulder on
  # one flank so they aren't plain triangles.
  ridge = { seed, base, step, lo, hi, ... }:
    let
      n = w / step + 2;
      tall = randoms seed n lo hi;
      nudge = randoms (seed + 1) n 0 (step / 2);
      shoulder = randoms (seed + 2) n 30 70;  # % of the peak's height
      peak = i:
        let
          x = i * step - step / 2 + builtins.elemAt nudge i;
          t = builtins.elemAt tall i;
          s = builtins.elemAt shoulder i;
        in pt (x - step / 2) base + pt (x - step / 4) (base - t * s / 100) + pt x (base - t);
    in closed base (lib.concatStrings (builtins.genList peak n));

  # Pines: a spire with three tiers of branches, standing on a line that
  # rolls by up to `roll` px. Spacing and height vary; width is a fraction
  # of the height (wide enough that neighbours overlap).
  pines = { seed, base, step, lo, hi, roll, width, ... }:
    let
      n = w / step + 2;
      tall = randoms seed n lo hi;
      gap = randoms (seed + 1) n 0 (step / 2);
      lift = randoms (seed + 2) n 0 (roll + 1);
      tree = i:
        let
          th = builtins.elemAt tall i;
          hw = th * width;
          cx = i * step + builtins.elemAt gap i;
          b = base - builtins.elemAt lift i;
          side = d: [ [ (cx + d * hw) b ]
                      [ (cx + d * hw * 0.35) (b - th * 0.3) ] [ (cx + d * hw * 0.75) (b - th * 0.3) ]
                      [ (cx + d * hw * 0.25) (b - th * 0.58) ] [ (cx + d * hw * 0.55) (b - th * 0.58) ]
                      [ (cx + d * hw * 0.15) (b - th * 0.8) ] [ (cx + d * hw * 0.32) (b - th * 0.8) ] ];
          points = side (-1) ++ [ [ cx (b - th) ] ] ++ lib.reverseList (side 1);
        in lib.concatMapStrings (q: pt (builtins.elemAt q 0) (builtins.elemAt q 1)) points;
    in closed base (lib.concatStrings (builtins.genList tree n));

  stars = let
      n = settings.sky.stars;
      xs = randoms settings.sky.starSeed n 0 w;
      ys = randoms (settings.sky.starSeed + 1) n 0 1200;
      rs = randoms (settings.sky.starSeed + 2) n 1 4;
    in lib.concatStrings (builtins.genList (i:
      ''<circle cx="${toString (builtins.elemAt xs i)}" cy="${toString (builtins.elemAt ys i)}" r="${toString (builtins.elemAt rs i)}" fill="#${c.fg}" opacity="0.5"/>'') n);

  shape = fill: d: ''<path d="${d}" fill="#${fill}"/>'';
  # A row of pines plus solid ground under their feet in the same colour.
  forest = row: shape (colour row.color) (pines row)
    + ''<rect y="${toString (row.base - row.roll)}" width="${toString w}" height="${toString h}" fill="#${colour row.color}"/>'';

  m = settings.moon;
  svg = pkgs.writeText "wallpaper.svg" ''
    <svg xmlns="http://www.w3.org/2000/svg" width="${toString w}" height="${toString h}">
      <defs>
        <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="#${c.bg}"/>
          <stop offset="0.75" stop-color="#${c.horizon}"/>
        </linearGradient>
        <radialGradient id="glow">
          <stop offset="0" stop-color="#${c.forest_text}" stop-opacity="0.18"/>
          <stop offset="1" stop-color="#${c.forest_text}" stop-opacity="0"/>
        </radialGradient>
      </defs>
      <rect width="${toString w}" height="${toString h}" fill="url(#sky)"/>
      ${stars}
      <circle cx="${toString m.x}" cy="${toString m.y}" r="${toString m.glow}" fill="url(#glow)"/>
      <circle cx="${toString m.x}" cy="${toString m.y}" r="${toString m.r}" fill="#${c.fg}"/>
      ${lib.concatMapStrings (r: shape (colour r.color) (ridge r)) settings.ridges}
      ${lib.concatMapStrings forest settings.pines}
    </svg>
  '';
in
pkgs.runCommand "wallpaper.png" { nativeBuildInputs = [ pkgs.librsvg ]; } ''
  rsvg-convert -w ${toString w} -h ${toString h} ${svg} -o $out
''
