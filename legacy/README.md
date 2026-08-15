# 276-byte AttoChess release

This directory preserves the exact predecessor used as the baseline for the
272-byte optimization campaign.

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| `AttoChess-276.asm` | 12,526 | `cb312e485613d83be28eb4e1a1a94606c65074958ce9e650f48e50c025856ae9` |
| `ATTOCHES-276.COM` | 276 | `856237bee9ef6040a03479f31df170b114f5a35f5aab70e5b7137728ef850a87` |

The source is the original MASM/TASM form. Build it with Turbo Assembler and
Turbo Linker:

```text
tasm AttoChess-276.asm
tlink /t AttoChess-276.obj
```

The repository's current [`AttoChess.asm`](../AttoChess.asm) is the licensed
NASM source for the 272-byte release.
