"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { createGame, makeMove, movesFrom, playReply, resultFor, squareName, type Game } from "../lib/chess";

const GLYPHS = {
  white: { k: "♔", q: "♕", r: "♖", b: "♗", n: "♘", p: "♙" },
  black: { k: "♚", q: "♛", r: "♜", b: "♝", n: "♞", p: "♟" },
};

const ideas = [
  ["01", "The board prints itself", "Border bytes double as line breaks, deleting an entire render buffer."],
  ["02", "Fast console output", "DOS INT 29h streams every byte straight to the screen."],
  ["03", "Constants disappear", "ASCII offsets are folded into one wrapping base address."],
  ["04", "CX stays live", "The source scan frees a register so search depth never reloads."],
  ["05", "Color becomes direction", "One color bit also tells pawns which way is forward."],
];
const INITIAL_MESSAGE = "White to move. Pick a piece.";
const lineage = [
  ["1K ZX Chess", "672", "1982", "David Horne"],
  ["BootChess", "487", "2015", "Olivier Poudade"],
  ["LeanChess", "288", "2019", "Dmitry Shechtman"],
  ["AttoChess", "278", "2026", "Nicholas Tanner"],
];

export default function Home() {
  const [game, setGame] = useState<Game>(createGame);
  const [selected, setSelected] = useState<number | null>(null);
  const [message, setMessage] = useState(INITIAL_MESSAGE);
  const [result, setResult] = useState<ReturnType<typeof resultFor> | null>(null);
  const [shareState, setShareState] = useState("");
  const [focused, setFocused] = useState(48);
  const squareRefs = useRef<Array<HTMLButtonElement | null>>([]);
  const legal = useMemo(() => new Set(selected === null ? [] : movesFrom(game.board, selected).map((move) => move.to)), [game.board, selected]);
  useEffect(() => { squareRefs.current[focused]?.focus(); }, [focused, game.history.length]);

  function selectSquare(index: number) {
    if (game.ended || result) return;
    const piece = game.board[index];
    if (selected !== null && legal.has(index)) {
      const moved = makeMove(game, { from: selected, to: index });
      const replied = playReply(moved);
      setGame(replied);
      setSelected(null);
      setFocused(index);
      if (replied.ended) {
        const finalResult = resultFor(replied);
        setResult(finalResult);
        setMessage(finalResult.headline);
      } else {
        setMessage(`278 bytes replied. White move ${replied.whiteMoves + 1} of 8.`);
      }
      return;
    }
    if (piece?.color === "white" && game.turn === "white") {
      setSelected(index);
      setMessage(`${squareName(index)} selected. Choose a highlighted square.`);
    } else {
      setSelected(null);
      setMessage("Choose one of your white pieces.");
    }
  }

  function reset() {
    setGame(createGame());
    setSelected(null);
    setResult(null);
    setShareState("");
    setMessage(INITIAL_MESSAGE);
    setFocused(48);
  }

  function endRun() {
    if (game.whiteMoves < 1) {
      setMessage("Make one move before ending the run.");
      return;
    }
    setResult(resultFor({ ...game, ended: true }));
  }

  async function share() {
    if (!result) return;
    const url = `${window.location.origin}${window.location.pathname}`;
    const text = `${result.headline} Score ${result.score}. A playable chess program fits in 278 bytes. Your move.`;
    try {
      if (navigator.share) {
        await navigator.share({ title: "The 278-Byte Chess Challenge", text, url });
        setShareState("Challenge shared.");
        return;
      }
      await navigator.clipboard.writeText(`${text} ${url}`);
      setShareState("Challenge copied.");
    } catch (error) {
      if (error instanceof DOMException && error.name === "AbortError") {
        setShareState("Share canceled.");
      } else {
        setShareState(`Copy this: ${text} ${url}`);
      }
    }
  }

  return (
    <main>
      <header className="topbar"><a href="#top" className="brand">ATTO<span>CHESS</span></a><a href="#how">How 278 bytes works ↓</a></header>
      <section className="hero" id="top">
        <div className="hero-copy">
          <p className="eyebrow">A playable chess program in just 278 bytes</p>
          <h1>CAN YOU BEAT<br /><em>278 BYTES?</em></h1>
          <p className="dek">The original AttoChess fits a board, input, and a four-ply opponent into less data than this paragraph. This web challenge is the larger, friendlier tribute.</p>
          <div className="size-row"><span>278 B</span><i /><span>A blank Word doc: ~12,000 B</span></div>
        </div>
        <div className="game-shell">
          <div className="terminal-line"><span>ATTOCHESS.COM</span><span>278 BYTES • WHITE TO MOVE</span></div>
          <div className="board" role="grid" aria-label="Chess challenge board">
            {game.board.map((piece, index) => {
              const active = selected === index;
              const target = legal.has(index);
              return <button
                key={index}
                ref={(node) => { squareRefs.current[index] = node; }}
                tabIndex={focused === index ? 0 : -1}
                className={`square ${(Math.floor(index / 8) + index) % 2 ? "dark" : "light"} ${active ? "selected" : ""} ${target ? "legal" : ""}`}
                onClick={() => selectSquare(index)}
                onKeyDown={(event) => {
                  if (event.key === "Escape") { setSelected(null); setMessage("Selection cleared."); }
                  const deltas: Record<string, number> = { ArrowLeft: -1, ArrowRight: 1, ArrowUp: -8, ArrowDown: 8 };
                  if (event.key in deltas) {
                    event.preventDefault();
                    const next = Math.max(0, Math.min(63, index + deltas[event.key]));
                    setFocused(next);
                  }
                }}
                onFocus={() => setFocused(index)}
                aria-label={`${squareName(index)} ${piece ? `${piece.color} ${piece.kind}` : "empty"}${target ? ", legal destination" : ""}`}
                aria-pressed={active}
              >{piece ? GLYPHS[piece.color][piece.kind] : ""}</button>;
            })}
          </div>
          <p className="status" aria-live="polite">{message}</p>
          <div className="controls">
            <button className="primary" onClick={result ? share : endRun}>{result ? "Share challenge" : "End & share"}</button>
            <button className="secondary" onClick={reset}>Reset</button>
          </div>
          {result && <div className="result"><p>{result.headline}</p><strong>{result.score}</strong><span>BYTE SCORE</span>{shareState && <small role="status" aria-live="polite">{shareState}</small>}</div>}
        </div>
      </section>

      <section className="marquee" aria-label="AttoChess facts"><span>278 BYTES</span><span>4-PLY SEARCH</span><span>16-BIT DOS</span><span>ZERO SERVERS</span></section>

      <section className="story" id="how">
        <div><p className="eyebrow">The impossible bit</p><h2>EVERY BYTE<br />DOES TWO JOBS.</h2></div>
        <p className="story-intro">AttoChess is ten bytes smaller than the previous record holder because it doesn’t merely remove features—it makes the remaining data carry more meaning.</p>
        <div className="idea-grid">{ideas.map(([number, title, body]) => <article key={number}><b>{number}</b><h3>{title}</h3><p>{body}</p></article>)}</div>
        <div className="lineage"><h3>The tiny-chess record line</h3>{lineage.map(([name, bytes, year, author]) => <div key={name}><strong>{name}</strong><span>{bytes} bytes</span><span>{year}</span><span>{author}</span></div>)}</div>
      </section>

      <section className="limits">
        <p className="eyebrow">Honest tiny print</p>
        <h2>SMALL ENOUGH<br />TO HAVE RULES.</h2>
        <p>The original plays real piece movement and recursive search, but omits castling, en passant, promotion, and full checkmate adjudication. This browser adaptation adds input guardrails; it is not itself 278 bytes.</p>
      </section>

      <footer>
        <p>AttoChess by Nicholas Tanner, descended from LeanChess by Dmitry Shechtman.</p>
        <nav><a href="https://github.com/Nicholas-afk/AttoChess">Source ↗</a><a href="https://leanchess.github.io/">LeanChess ↗</a><a href="/third-party-notices.txt">License ↗</a></nav>
        <small>Copyright (c) 2026 Nicholas Tanner · Copyright (c) 2019 Dmitry Shechtman</small>
      </footer>
    </main>
  );
}
