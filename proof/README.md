# Proof and differential evidence

This directory binds the exact 272-byte release to eight standalone SMT-LIB
mismatch queries and one canonical emulator report.

## Artifact fingerprints

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| `../AttoChess.asm` | 6,343 | `2dda33f61b4d1665f01138cbaf78f79636eabd71017abbc77efdaac13e807400` |
| `../ATTOCHES.COM` | 272 | `02b80d2b11ba3c6bea02b112e7009c318aac35b3e869f8bb823dc2aa6cdd6f8e` |
| `../legacy/AttoChess-276.asm` | 12,526 | `cb312e485613d83be28eb4e1a1a94606c65074958ce9e650f48e50c025856ae9` |
| `../legacy/ATTOCHES-276.COM` | 276 | `856237bee9ef6040a03479f31df170b114f5a35f5aab70e5b7137728ef850a87` |
| `differential.json` | 11,895 | `ab632e7a55ed9ce43f26dae4803080e17c0b625b072a7fa23976f30b537b59f3` |

## Z3 obligations

All eight queries returned `UNSAT` under Z3 4.16.0. The formula and captured
native proof hashes are:

| Query | Formula SHA-256 | Native proof SHA-256 |
|---|---|---|
| `move_prologue_equivalence` | `1271d231d56f7ad1bfa5889e9d1a6332b787b962f6e2f3091af8c0a50205724e` | `b43e34c76a0bccefa6ccca9eef4ee5425e574b5fdad25ec2f16c3132a2e38567` |
| `pawn_predicate_equivalence` | `a25c0b03790eb295a18329c50e01d1e8a56e9e8b97f15bdb86dad76cfe837dad` | `31d20b708ba06be00371e86559c44643f3b302080407c3a5571b222fca545c14` |
| `pawn_recursive_dead_inputs` | `2b4c12c2b93d71e943540f8f9ef5ff381d695c90c6bb1e42b508e937f3313f17` | `dc700316b27920b0e44a89a97bde720be01197221c4f63c182820102a7e4df50` |
| `pawn_undo_equivalence` | `2b2e37a2d6baffa68a9c7bcd46b07bfaf9eff41e6b595fef85f1b69759e4c095` | `a02886f6c03e780cc7f4fccdf3b9c29cd0890828aa314e3eb67ba487eb69c1e6` |
| `pawn_contextual_equivalence` | `6171ea0fff15d5f4d98d2bec5e4ee73ac9f829aed5375da2865748fee7b8ea58` | `a86a17a4488f9be892900acabbacbc29bd8b3aa0b677fc2de3a42dbff8fd16bc` |
| `table_overlap_equivalence` | `35de233212d37a948872655fccf6fbcfb0bbfae5a9a6aea91a9e794b3b8f6349` | `1654e35a2bac288f0a79a8a5a1ae5564f98b554add874b159ad9c0a4a306e9a9` |
| `pointer_metadata_equivalence` | `bcbd1ace1e11a66d8fc06e53d4938272962da49ea407fb9019f8ced72fde6bf7` | `80bf7406c3d60e3e1421240adf2a261d2e7cba4201624811eebb2a9600d37ff3` |
| `rejected_clone_deadness` | `7ec1039ad5bfff679ea8f84d19a064dd946c99f98a4402d230541df860821acd` | `d497db83080031cdbd2a80d4ecd99f013998e49b87685774ea71853981a97e71` |

Replay any query with a compatible Z3 build:

```sh
z3 proof/queries/pointer_metadata_equivalence.smt2
```

Each query enables proof production and includes `(check-sat)` followed by
`(get-proof)`, so replay prints `unsat` and then Z3's proof expression. The
matching file under `proofs/` contains the originally captured proof expression
without the status line. Files under `stats/` contain solver statistics from
the embedded verification run.

Z3 proof expressions are internal solver objects, not standardized
certificates checked by an independent proof kernel. The trusted base includes
Z3, the formula generator, the instruction semantics, and the declared
contextual assumptions.

## Structural evidence

The proof-producing audit additionally checked:

- exact 80186 instruction boundaries and byte-identical re-encoding;
- executable ranges `[0000h,0055h)` and `[005Bh,00E4h)`;
- no control-flow edge or fallthrough into the six-byte metadata island;
- byte-lane register and memory liveness;
- `BH=01h` dominance and nested `PUSHA`/`POPA` restoration;
- three pre-evaluation reject edges for `AH`/`BH` read-before-kill; and
- evaluation `PUSHA` plus recursive `CALL` dominance over the undo join.

## Differential execution

`differential.json` is the canonical Unicorn 2.1.4 report. It compares the
original 276-byte and final 272-byte images across all 20 legal opening moves
and three selected two-turn sequences. Complete modeled DOS echo/output event
traces and relocated board state matched in all 23 runs. Hidden border offsets
4–11 are the only representation-only exclusions; their blocker equivalence is
covered by the table-overlap query.

To reproduce it, install Unicorn's Python package, preserve the two canonical
input basenames recorded in the report, and run:

```sh
mkdir -p /tmp/attochess-differential
cp legacy/ATTOCHES-276.COM /tmp/attochess-differential/ATTOCHES.COM
cp ATTOCHES.COM /tmp/attochess-differential/ATTOCHES-272.COM
python3 tools/differential_unicorn.py \
  --canonical-suite \
  --json-report /tmp/attochess-differential/differential.json \
  /tmp/attochess-differential/ATTOCHES.COM \
  /tmp/attochess-differential/ATTOCHES-272.COM
shasum -a 256 /tmp/attochess-differential/differential.json
```

The expected report hash is
`ab632e7a55ed9ce43f26dae4803080e17c0b625b072a7fa23976f30b537b59f3`.

## Exact claim boundary

These are local and contextual equivalence obligations for four specific
reductions. `pawn_contextual_equivalence` takes equal recursive score as an
explicit composition hypothesis. The evidence does not prove an unbounded
whole-program bisimulation or that no unrelated 271-byte x86 chess program can
exist.
