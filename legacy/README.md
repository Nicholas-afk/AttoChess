# Previous AttoChess builds

This directory preserves the 276-byte baseline and the original 272-byte
build before the losing-reply fix.

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| `AttoChess-276.asm` | 12,526 | `cb312e485613d83be28eb4e1a1a94606c65074958ce9e650f48e50c025856ae9` |
| `ATTOCHES-276.COM` | 276 | `856237bee9ef6040a03479f31df170b114f5a35f5aab70e5b7137728ef850a87` |

The 276-byte source is the original MASM/TASM form. Build it with Turbo Assembler and
Turbo Linker:

```text
tasm AttoChess-276.asm
tlink /t AttoChess-276.obj
```

The repository's current [`AttoChess.asm`](../AttoChess.asm) is the licensed
NASM source for the 272-byte release.

The previous zero-floor 272-byte build is preserved as
`AttoChess-272-zero-floor.asm` and `ATTOCHES-272-zero-floor.COM`. Its source
SHA-256 is `2dda33f61b4d1665f01138cbaf78f79636eabd71017abbc77efdaac13e807400`;
its executable SHA-256 is
`02b80d2b11ba3c6bea02b112e7009c318aac35b3e869f8bb823dc2aa6cdd6f8e`.
Build it with `nasm -f bin -w+error -o ATTOCHES-272-zero-floor.COM AttoChess-272-zero-floor.asm`.
The corresponding evidence is documented in
[`proof/previous-272.md`](../proof/previous-272.md).
