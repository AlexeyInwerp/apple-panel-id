import subprocess, plistlib
raw = subprocess.run(["ioreg","-arw0","-c","AppleTCONComponent"],
                     capture_output=True).stdout
d = plistlib.loads(raw)
def s(x):
    return x.rstrip(b"\x00").decode("ascii","replace") if isinstance(x,(bytes,bytearray)) else str(x)
print("%-16s %-24s %-6s %-7s prot verify" % ("COMPONENT","BUS/TYPE","ADDR","SIZE"))
for c in d:
    reg = c.get("reg", b"")
    addr = int.from_bytes(reg[0:4],"little") if len(reg)>=8 else 0
    size = int.from_bytes(reg[4:8],"little") if len(reg)>=8 else 0
    iface = int.from_bytes(c.get("interface", b"\0")[:4],"little")
    prot  = int.from_bytes(c.get("protection",b"\0")[:4],"little")
    ver   = int.from_bytes(c.get("verify",    b"\0")[:4],"little")
    bus = {0:"SPI",3:"I2C"}.get(iface, "if%d"%iface)
    print("%-16s %-24s 0x%02x   0x%-5x %d    %d" %
          (s(c.get("name")), bus+"/"+s(c.get("device_type")), addr, size, prot, ver))
