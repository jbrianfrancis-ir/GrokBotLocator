#!/usr/bin/env python3
"""Generate GPX fixtures for phase 04's device checks (REQ-06, REQ-08).

Offsets are computed on the WGS84 meridian arc, NOT the flat `metres / 111_320`
approximation. That approximation is ~1.2 m out at 500 m -- enough to land an
"exactly 500 m" case on the wrong side of DisplacementGate's `>=`, which is the
defect plan 04-03 hit and fixed by bisection. Movement is due north, so
longitude is unchanged and the meridian arc is the exact answer.

Usage:  make-routes.py [LAT] [LON]      (defaults to Gallipoli, Puglia)
"""
import math
import sys
from datetime import datetime, timedelta, timezone

OUT = __file__.rsplit("/", 1)[0]


def metres_per_degree_latitude(lat_deg: float) -> float:
    """WGS84 meridian arc length per degree of latitude at this latitude."""
    p = math.radians(lat_deg)
    return (111132.92
            - 559.82 * math.cos(2 * p)
            + 1.175 * math.cos(4 * p)
            - 0.0023 * math.cos(6 * p))


def north(lat: float, metres: float) -> float:
    """Latitude `metres` due north of `lat`, refining once for the arc's own drift."""
    guess = lat + metres / metres_per_degree_latitude(lat)
    mid = (lat + guess) / 2.0
    return lat + metres / metres_per_degree_latitude(mid)


def haversine(a_lat, a_lon, b_lat, b_lon) -> float:
    """Independent check of the offsets, on the mean-earth sphere CLLocation approximates."""
    r = 6371008.8
    p1, p2 = math.radians(a_lat), math.radians(b_lat)
    dp = p2 - p1
    dl = math.radians(b_lon - a_lon)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


def write(name: str, points, note: str) -> None:
    """A GPX with <time> on each waypoint; Xcode interpolates between them."""
    t0 = datetime(2026, 1, 1, 12, 0, 0, tzinfo=timezone.utc)
    body = []
    for i, (lat, lon, label) in enumerate(points):
        stamp = (t0 + timedelta(seconds=i * 60)).strftime("%Y-%m-%dT%H:%M:%SZ")
        body.append(f'  <wpt lat="{lat:.7f}" lon="{lon:.7f}">\n'
                    f'    <name>{label}</name>\n'
                    f'    <time>{stamp}</time>\n'
                    f'  </wpt>')
    doc = ('<?xml version="1.0" encoding="UTF-8"?>\n'
           f'<!-- {note} -->\n'
           '<gpx version="1.1" creator="GrokBotLocator phase 04 device checks"\n'
           '     xmlns="http://www.topografix.com/GPX/1/1">\n'
           + "\n".join(body) + "\n</gpx>\n")
    with open(f"{OUT}/{name}", "w") as fh:
        fh.write(doc)


def main() -> None:
    lat = float(sys.argv[1]) if len(sys.argv) > 1 else 40.0559
    lon = float(sys.argv[2]) if len(sys.argv) > 2 else 17.9925

    # REQ-06: 300 m must NOT ping, 520 m must. 520 not 500 -- the boundary case
    # belongs in the unit suite (it has one), not in a hand-run device check
    # where GPS noise decides it.
    p300 = north(lat, 300.0)
    p520 = north(lat, 520.0)
    # REQ-08: geofence radius is 150 m. Two successive 200 m hops; the SECOND is
    # what proves re-registration rather than a stuck original region.
    hop1 = north(lat, 200.0)
    hop2 = north(hop1, 200.0)

    write("req06-start.gpx", [(lat, lon, "Start / reference")],
          "REQ-06 + REQ-08 origin. Select this first and let it settle.")
    write("req06-300m-no-ping.gpx",
          [(lat, lon, "Start"), (p300, lon, "300 m north")],
          "REQ-06 NEGATIVE: 300 m. Expect NO automatic ping.")
    write("req06-520m-ping.gpx",
          [(lat, lon, "Start"), (p520, lon, "520 m north")],
          "REQ-06 POSITIVE: 520 m, past the 500 m gate. Expect exactly ONE ping.")
    write("req08-hop1.gpx", [(hop1, lon, "200 m from the manual ping")],
          "REQ-08 first exit: >150 m from where the manual ping registered.")
    write("req08-hop2.gpx", [(hop2, lon, "200 m from hop 1")],
          "REQ-08 second exit: proves the region was RE-registered at hop 1.")

    print(f"origin {lat:.6f}, {lon:.6f}\n")
    for label, target in (("300 m (no ping)", p300), ("520 m (ping)", p520),
                          ("hop1 200 m", hop1)):
        print(f"  {label:<18} lat {target:.7f}  "
              f"haversine check: {haversine(lat, lon, target, lon):8.2f} m")
    print(f"  {'hop2 200 m':<18} lat {hop2:.7f}  "
          f"haversine check: {haversine(hop1, lon, hop2, lon):8.2f} m (from hop1)")
    print(f"  {'hop2 from origin':<18} "
          f"{haversine(lat, lon, hop2, lon):.2f} m")


if __name__ == "__main__":
    main()
