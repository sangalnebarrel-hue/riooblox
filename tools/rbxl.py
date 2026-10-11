"""Minimal, fidelity-first Roblox binary place (.rbxl) reader/patcher.

Design goal: every chunk we do not touch is written back byte-for-byte (including its
original compression). We only re-encode the chunks we have to change:
  * PROP chunks of classes whose instances we edit or add,
  * INST chunks of classes we add instances to,
  * the PRNT chunk when instances are added,
  * the file header instance count.

New instances are created by cloning an existing "template" instance of the same class:
every property array gets one more value copied from the template, then selected
properties (Name, Source, UniqueId-like ids) are overridden.
"""
import hashlib
import os
import struct

import lz4.block
import zstandard

MAGIC = b"<roblox!\x89\xff\r\n\x1a\n"

T_STRING = 0x01
T_BOOL = 0x02
T_INT32 = 0x03
T_FLOAT32 = 0x04
T_FLOAT64 = 0x05
T_UDIM = 0x06
T_UDIM2 = 0x07
T_RAY = 0x08
T_FACES = 0x09
T_AXES = 0x0A
T_BRICKCOLOR = 0x0B
T_COLOR3 = 0x0C
T_VECTOR2 = 0x0D
T_VECTOR3 = 0x0E
T_CFRAME = 0x10
T_ENUM = 0x12
T_REF = 0x13
T_V3I16 = 0x14
T_NUMSEQ = 0x15
T_COLORSEQ = 0x16
T_NUMRANGE = 0x17
T_RECT = 0x18
T_PHYS = 0x19
T_COLOR3U8 = 0x1A
T_INT64 = 0x1B
T_SHAREDSTRING = 0x1C
T_BYTECODE = 0x1D
T_OPTCFRAME = 0x1E
T_UNIQUEID = 0x1F
T_FONT = 0x20
T_SECCAP = 0x21
T_CONTENT = 0x22

# Fixed-width interleaved types: width in bytes per value.
INTERLEAVED_WIDTH = {
    T_INT32: 4,
    T_FLOAT32: 4,
    T_ENUM: 4,
    T_SHAREDSTRING: 4,
    T_INT64: 8,
    T_UNIQUEID: 16,
    T_SECCAP: 8,
    T_BRICKCOLOR: 4,
}
# Fixed-width, non-interleaved types.
PLAIN_WIDTH = {
    T_BOOL: 1,
    T_FLOAT64: 8,
    T_FACES: 1,
    T_AXES: 1,
}


def deinterleave(buf, count, width):
    out = []
    for i in range(count):
        out.append(bytes(buf[j * count + i] for j in range(width)))
    return out


def interleave(values, width):
    count = len(values)
    out = bytearray(count * width)
    for i, v in enumerate(values):
        assert len(v) == width
        for j in range(width):
            out[j * count + i] = v[j]
    return bytes(out)


def zz_dec32(u):
    return (u >> 1) ^ -(u & 1)


def zz_enc32(n):
    return ((n << 1) ^ (n >> 31)) & 0xFFFFFFFF


def read_refs(buf, off, count):
    raw = deinterleave(buf[off:off + 4 * count], count, 4)
    refs = []
    acc = 0
    for r in raw:
        acc += zz_dec32(struct.unpack(">I", r)[0])
        refs.append(acc)
    return refs, off + 4 * count


def write_refs(refs):
    raw = []
    prev = 0
    for r in refs:
        raw.append(struct.pack(">I", zz_enc32(r - prev)))
        prev = r
    return interleave(raw, 4)


def read_str(buf, off):
    (n,) = struct.unpack_from("<I", buf, off)
    return bytes(buf[off + 4:off + 4 + n]), off + 4 + n


def pack_str(b):
    if isinstance(b, str):
        b = b.encode("utf-8")
    return struct.pack("<I", len(b)) + b


class Chunk:
    def __init__(self, name, raw_header, raw_payload, body):
        self.name = name
        self.raw_header = raw_header  # original 16-byte header (for verbatim writes)
        self.raw_payload = raw_payload  # original (maybe compressed) payload
        self.body = body  # decompressed body
        self.dirty = False

    def set_body(self, body):
        self.body = body
        self.dirty = True

    def serialize(self):
        if not self.dirty:
            return self.raw_header + self.raw_payload
        comp = zstandard.ZstdCompressor(level=19).compress(self.body)
        if len(comp) >= len(self.body):
            return self.name + struct.pack("<III", 0, len(self.body), 0) + self.body
        return self.name + struct.pack("<III", len(comp), len(self.body), 0) + comp


class Place:
    def __init__(self, path):
        data = open(path, "rb").read()
        assert data[:14] == MAGIC, "not a binary roblox file"
        self.header = bytearray(data[:32])
        (self.version,) = struct.unpack_from("<H", data, 14)
        self.num_classes, self.num_instances = struct.unpack_from("<ii", data, 16)
        self.chunks = []
        off = 32
        while off < len(data):
            name = data[off:off + 4]
            clen, ulen, _ = struct.unpack_from("<III", data, off + 4)
            hdr = data[off:off + 16]
            off += 16
            if clen == 0:
                payload = data[off:off + ulen]
                body = payload
                off += ulen
            else:
                payload = data[off:off + clen]
                off += clen
                if payload[:4] == b"\x28\xb5\x2f\xfd":
                    body = zstandard.ZstdDecompressor().decompress(payload, max_output_size=ulen)
                else:
                    body = lz4.block.decompress(payload, uncompressed_size=ulen)
            self.chunks.append(Chunk(name, hdr, payload, body))
            if name == b"END\x00":
                break
        self._index()

    # ------------------------------------------------------------------ parsing
    def _index(self):
        self.classes = {}  # cid -> dict(name, fmt, refs, chunk)
        self.class_by_name = {}
        self.props = {}  # cid -> {pname: chunk}
        self.prop_order = {}
        self.ref_class = {}  # ref -> (cid, index)
        self.sstr = []
        for ch in self.chunks:
            if ch.name == b"INST":
                b = ch.body
                (cid,) = struct.unpack_from("<i", b, 0)
                cname, off = read_str(b, 4)
                fmt = b[off]
                (n,) = struct.unpack_from("<I", b, off + 1)
                refs, off2 = read_refs(b, off + 5, n)
                extra = b[off2:]
                info = dict(cid=cid, name=cname.decode(), fmt=fmt, refs=refs, chunk=ch, extra=extra)
                self.classes[cid] = info
                self.class_by_name[info["name"]] = info
                for i, r in enumerate(refs):
                    self.ref_class[r] = (cid, i)
            elif ch.name == b"PROP":
                b = ch.body
                (cid,) = struct.unpack_from("<i", b, 0)
                pname, off = read_str(b, 4)
                self.props.setdefault(cid, {})[pname.decode()] = ch
                self.prop_order.setdefault(cid, []).append(pname.decode())
            elif ch.name == b"PRNT":
                b = ch.body
                (n,) = struct.unpack_from("<I", b, 1)
                kids, off = read_refs(b, 5, n)
                pars, off = read_refs(b, off, n)
                self.prnt_chunk = ch
                self.parent_of = dict(zip(kids, pars))
                self.prnt_order = kids
            elif ch.name == b"SSTR":
                b = ch.body
                (ver, n) = struct.unpack_from("<II", b, 0)
                off = 8
                for _ in range(n):
                    h = b[off:off + 16]
                    s, off = read_str(b, off + 16)
                    self.sstr.append((h, s))
                self.sstr_chunk = ch
        self.children_of = {}
        for k in self.prnt_order:
            self.children_of.setdefault(self.parent_of[k], []).append(k)

    def prop_values(self, cid, pname):
        """Return (type, list_of_raw_values) where raw values are per-instance bytes."""
        ch = self.props[cid][pname]
        b = ch.body
        _, off = read_str(b, 4)
        t = b[off]
        off += 1
        n = len(self.classes[cid]["refs"])
        return t, decode_values(t, b, off, n)

    def set_prop_values(self, cid, pname, t, values):
        body = struct.pack("<i", cid) + pack_str(pname) + bytes([t]) + encode_values(t, values)
        self.props[cid][pname].set_body(body)

    def name_of(self, ref):
        cid, i = self.ref_class[ref]
        t, vals = self.prop_values(cid, "Name")
        return vals[i].decode("utf-8", "replace")

    def class_of(self, ref):
        return self.classes[self.ref_class[ref][0]]["name"]

    def path_of(self, ref):
        parts = []
        r = ref
        while r != -1 and r in self.ref_class:
            parts.append(self.name_of(r))
            r = self.parent_of.get(r, -1)
        return "/".join(reversed(parts))

    def find_by_path(self, path):
        """Path like 'ReplicatedStorage/DogEconomy/Config'. Returns list of refs (should be 1)."""
        names = path.split("/")
        current = [r for r in self.children_of.get(-1, []) if self.name_of(r) == names[0]]
        for nm in names[1:]:
            nxt = []
            for r in current:
                nxt.extend(k for k in self.children_of.get(r, []) if self.name_of(k) == nm)
            current = nxt
        return current

    # ----------------------------------------------------------------- patching
    def set_string_prop(self, ref, pname, value):
        cid, i = self.ref_class[ref]
        t, vals = self.prop_values(cid, pname)
        assert t == T_STRING, (pname, t)
        vals[i] = value.encode("utf-8") if isinstance(value, str) else value
        self.set_prop_values(cid, pname, t, vals)

    def get_string_prop(self, ref, pname):
        cid, i = self.ref_class[ref]
        t, vals = self.prop_values(cid, pname)
        assert t == T_STRING
        return vals[i].decode("utf-8")

    def get_bool_prop(self, ref, pname):
        cid, i = self.ref_class[ref]
        t, vals = self.prop_values(cid, pname)
        assert t == T_BOOL
        return vals[i] != b"\x00"

    def clone_instance(self, template_ref, parent_ref, overrides):
        """Append a new instance of the template's class. overrides: {pname: (kind, value)}"""
        cid, ti = self.ref_class[template_ref]
        info = self.classes[cid]
        assert info["fmt"] == 0, "cannot clone service-format instances"
        new_ref = max(self.ref_class) + 1
        # INST
        info["refs"].append(new_ref)
        self.ref_class[new_ref] = (cid, len(info["refs"]) - 1)
        body = struct.pack("<i", cid) + pack_str(info["name"]) + bytes([info["fmt"]]) + struct.pack("<I", len(info["refs"])) + write_refs(info["refs"]) + info["extra"]
        info["chunk"].set_body(body)
        # PROPs
        for pname in self.prop_order[cid]:
            ch = self.props[cid][pname]
            b = ch.body
            _, off = read_str(b, 4)
            t = b[off]
            n_old = len(info["refs"]) - 1
            vals = decode_values(t, b, off + 1, n_old)
            v = vals[ti]
            if pname in overrides:
                v = overrides[pname](t, v) if callable(overrides[pname]) else overrides[pname]
            elif t == T_UNIQUEID:
                v = fresh_unique_id(v)
            elif t == T_STRING and pname == "ScriptGuid":
                v = ("{%s}" % fresh_guid()).encode()
            vals.append(v)
            body = struct.pack("<i", cid) + pack_str(pname) + bytes([t]) + encode_values(t, vals)
            ch.set_body(body)
        # PRNT
        self.prnt_order.append(new_ref)
        self.parent_of[new_ref] = parent_ref
        self.children_of.setdefault(parent_ref, []).append(new_ref)
        pb = bytes([0]) + struct.pack("<I", len(self.prnt_order)) + write_refs(self.prnt_order) + write_refs([self.parent_of[k] for k in self.prnt_order])
        self.prnt_chunk.set_body(pb)
        self.num_instances += 1
        struct.pack_into("<i", self.header, 20, self.num_instances)
        return new_ref

    def save(self, path):
        with open(path, "wb") as f:
            f.write(bytes(self.header))
            for ch in self.chunks:
                f.write(ch.serialize())


_uid_counter = [0]


def fresh_unique_id(template_bytes):
    """UniqueId values are 16 bytes; mutate the random part deterministically-unique."""
    _uid_counter[0] += 1
    rnd = os.urandom(8)
    # layout (rbx-dom): index u32, time u32, random i64 — we replace all with fresh data
    return rnd + os.urandom(4) + struct.pack(">I", 0x40000000 + _uid_counter[0])


def fresh_guid():
    h = os.urandom(16).hex().upper()
    return "%s-%s-%s-%s-%s" % (h[:8], h[8:12], h[12:16], h[16:20], h[20:])


def decode_values(t, b, off, n):
    if t == T_STRING:
        out = []
        for _ in range(n):
            s, off = read_str(b, off)
            out.append(s)
        assert off == len(b), "string array length mismatch"
        return out
    if t in INTERLEAVED_WIDTH:
        w = INTERLEAVED_WIDTH[t]
        assert len(b) - off == w * n, ("interleaved size mismatch", t, len(b) - off, w * n)
        return deinterleave(b[off:], n, w)
    if t in PLAIN_WIDTH:
        w = PLAIN_WIDTH[t]
        assert len(b) - off == w * n
        return [bytes(b[off + i * w: off + (i + 1) * w]) for i in range(n)]
    if t in (T_COLOR3, T_VECTOR2, T_VECTOR3):
        k = {T_COLOR3: 3, T_VECTOR2: 2, T_VECTOR3: 3}[t]
        assert len(b) - off == 4 * k * n
        comps = [deinterleave(b[off + c * 4 * n: off + (c + 1) * 4 * n], n, 4) for c in range(k)]
        return [b"".join(comps[c][i] for c in range(k)) for i in range(n)]
    raise NotImplementedError("property type 0x%02x not supported for re-encoding" % t)


def encode_values(t, vals):
    if t == T_STRING:
        return b"".join(pack_str(v) for v in vals)
    if t in INTERLEAVED_WIDTH:
        return interleave(vals, INTERLEAVED_WIDTH[t])
    if t in PLAIN_WIDTH:
        return b"".join(vals)
    if t in (T_COLOR3, T_VECTOR2, T_VECTOR3):
        k = {T_COLOR3: 3, T_VECTOR2: 2, T_VECTOR3: 3}[t]
        return b"".join(interleave([v[c * 4:(c + 1) * 4] for v in vals], 4) for c in range(k))
    raise NotImplementedError("property type 0x%02x" % t)
