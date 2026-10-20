"""Extract a tar stream from an HFS volume into argv[1], decoding Mac Roman file names."""
import sys, tarfile
n = 0
with tarfile.open(fileobj=sys.stdin.buffer, mode="r|") as t:
    for m in t:
        raw = m.name.encode("utf-8", "surrogateescape")
        try:
            raw.decode("utf-8")
        except UnicodeDecodeError:
            m.name = raw.decode("mac_roman")
        t.extract(m, sys.argv[1], filter="data")
        n += 1
print(f"  extracted {n} entries", flush=True)
