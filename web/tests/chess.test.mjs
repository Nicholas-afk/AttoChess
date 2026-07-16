import assert from "node:assert/strict";
import test from "node:test";
import { allMoves, chooseReply, createGame, makeMove, movesFrom, playReply, resultFor, squareIndex } from "../lib/chess.ts";

test("accepts e2e4 and rejects e2e5", () => {
  const game = createGame();
  const from = squareIndex("e2");
  assert(movesFrom(game.board, from).some((move) => move.to === squareIndex("e4")));
  assert(!movesFrom(game.board, from).some((move) => move.to === squareIndex("e5")));
  assert.equal(makeMove(game, { from, to: squareIndex("e5") }), game);
});

test("reply is deterministic and bounded", () => {
  const game = makeMove(createGame(), { from: squareIndex("e2"), to: squareIndex("e4") });
  const first = chooseReply(game);
  const second = chooseReply(game);
  assert.deepEqual(first, second);
  assert(first.leaves <= 20_000);
  assert.equal(playReply(game).turn, "white");
  assert.equal(first.move.from, squareIndex("b8"));
  assert.equal(first.move.to, squareIndex("c6"));
});

test("standard position exposes twenty white moves", () => {
  assert.equal(allMoves(createGame().board, "white").length, 20);
});

test("result scoring is stable", () => {
  const game = { ...createGame(), whiteMoves: 3, capturedByWhite: 4, capturedByBlack: 1, ended: true };
  assert.deepEqual(resultFor(game), { score: 118, headline: "You survived 3 moves." });
});

test("king capture ends the run without adding material score", () => {
  const game = createGame();
  game.board = Array(64).fill(null);
  game.board[squareIndex("e1")] = { color: "white", kind: "k" };
  game.board[squareIndex("e7")] = { color: "white", kind: "r" };
  game.board[squareIndex("e8")] = { color: "black", kind: "k" };
  const won = makeMove(game, { from: squareIndex("e7"), to: squareIndex("e8") });
  assert.equal(won.winner, "white");
  assert.equal(won.ended, true);
  assert.equal(won.capturedByWhite, 0);
  assert.equal(resultFor(won).score, 105);
});

test("black reply after white move eight ends the run", () => {
  const game = { ...createGame(), whiteMoves: 7 };
  const white = makeMove(game, { from: squareIndex("e2"), to: squareIndex("e4") });
  const finished = playReply(white);
  assert.equal(finished.whiteMoves, 8);
  assert.equal(finished.ended, true);
});
