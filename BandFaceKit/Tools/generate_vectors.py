#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Незалежна еталонна реалізація для тест-векторів BandFaceKit.

Використовує бібліотеку `cryptography` (AES, AES-CCM, HKDF) і стандартні hashlib/zlib,
щоб перевірити саморобні режими CTR і CCM у Swift-коді.

    pip install cryptography
    python3 Tools/generate_vectors.py
"""
import hashlib
import hmac
import struct
import zlib

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.ciphers.aead import AESCCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF


def crc16_arc(data: bytes) -> int:
    crc = 0
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = (crc >> 1) ^ 0xA001 if crc & 1 else crc >> 1
    return crc


def frame(ftype: int, seq: int, payload: bytes) -> bytes:
    crc = crc16_arc(payload) if payload else 0
    return b"\xa5\xa5" + bytes([ftype, seq]) + struct.pack("<HH", len(payload), crc) + payload


# --- мінімальний protobuf ---
def varint(v: int) -> bytes:
    out = bytearray()
    while v >= 0x80:
        out.append((v & 0x7F) | 0x80)
        v >>= 7
    out.append(v)
    return bytes(out)


def f_varint(n, v):
    return varint(n << 3) + varint(v)


def f_bytes(n, b):
    return varint((n << 3) | 2) + varint(len(b)) + b


def f_float(n, x):
    return varint((n << 3) | 5) + struct.pack("<f", x)


def command(t, st, rest=b""):
    return f_varint(1, t) + f_varint(2, st) + rest


def aes_ctr(key, iv, data):
    c = Cipher(algorithms.AES(key), modes.CTR(iv)).encryptor()
    return c.update(data) + c.finalize()


def h(b: bytes) -> str:
    return b.hex()


def main():
    print("crc16(123456789) =", hex(crc16_arc(b"123456789")))
    print("crc32(123456789) =", hex(zlib.crc32(b"123456789")))

    open_payload = bytes.fromhex("01" "010300010000" "020200" "00fc" "030200" "2000" "040200" "1027")
    assert len(open_payload) == 22
    print("open frame       =", h(frame(2, 0, open_payload)))
    print("close frame      =", h(frame(2, 0, b"\x03")))
    print("ack 7            =", h(frame(1, 7, b"")))

    K = bytes(range(16))
    P = bytes(range(0x10, 0x20))
    W = bytes(range(0x20, 0x30))

    okm = HKDF(algorithm=hashes.SHA256(), length=64, salt=P + W, info=b"miwear-auth").derive(K)
    kd, ke, nd, ne = okm[0:16], okm[16:32], okm[32:36], okm[36:40]
    print("Kd =", h(kd)); print("Ke =", h(ke)); print("Nd =", h(nd)); print("Ne =", h(ne))
    print("band hmac    =", h(hmac.new(kd, W + P, hashlib.sha256).digest()))
    print("confirmation =", h(hmac.new(ke, P + W, hashlib.sha256).digest()))

    phone_info = f_varint(1, 0) + f_float(2, 34.0) + f_bytes(3, b"iPhone") + f_varint(4, 224) + f_bytes(5, b"UK")
    print("phone info   =", h(phone_info))
    enc_info = AESCCM(ke, tag_length=4).encrypt(ne + b"\x00" * 8, phone_info, None)
    print("phone info enc =", h(enc_info))

    step1 = command(1, 26, f_bytes(3, f_bytes(30, f_bytes(1, P))))
    print("auth step1 body =", h(step1))

    dev = command(2, 2)
    print("2/2 body =", h(dev))
    print("2/2 enc  =", h(aes_ctr(ke, ke, dev)))
    long_body = bytes(range(40))  # кілька блоків: перевіряє інкремент лічильника
    print("ctr40 enc (Kd) =", h(aes_ctr(kd, kd, long_body)))

    install = command(4, 4, f_bytes(6, f_bytes(6, f_bytes(1, b"266235369") + f_varint(2, 103424))))
    print("4/4 body =", h(install))
    md5 = hashlib.md5(b"hello").digest()
    upload = command(22, 0, f_bytes(24, f_bytes(1, f_varint(1, 16) + f_bytes(2, md5) + f_varint(3, 5))))
    print("22/0 body =", h(upload))

    # Потік файлу і частини
    file = bytes((i * 7) & 0xFF for i in range(10000))
    fmd5 = hashlib.md5(file).digest()
    stream = b"\x00\x10" + fmd5 + struct.pack("<I", len(file)) + file
    stream += struct.pack("<I", zlib.crc32(stream))
    part_len = 4096 - 4
    total = -(-len(stream) // part_len)
    print("file md5 =", h(fmd5), "stream len", len(stream), "crc", h(stream[-4:]), "parts", total)
    last = stream[(total - 1) * part_len:]
    print("last part len", len(last) + 4, "first part head", h(struct.pack("<HH", total, 1) + stream[:8]))

    # resume from 5000
    stream2 = b"\x00\x10" + fmd5 + struct.pack("<I", len(file)) + file[5000:]
    stream2 += struct.pack("<I", zlib.crc32(stream2))
    print("resume crc", h(stream2[-4:]), "len", len(stream2))


if __name__ == "__main__":
    main()
