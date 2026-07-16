export type Color = "white" | "black";
export type PieceKind = "p" | "n" | "b" | "r" | "q" | "k";
export type Piece = { color: Color; kind: PieceKind };
export type Board = Array<Piece | null>;
export type Move = { from: number; to: number; capture?: Piece };
export type Game = {
  board: Board;
  turn: Color;
  history: Move[];
  whiteMoves: number;
  capturedByWhite: number;
  capturedByBlack: number;
  winner: Color | null;
  ended: boolean;
  evaluatedLeaves: number;
};

const BACK: PieceKind[] = ["r", "n", "b", "q", "k", "b", "n", "r"];
const VALUE: Record<PieceKind, number> = { p: 1, n: 3, b: 3, r: 5, q: 9, k: 100 };
const SCORE_VALUE: Record<PieceKind, number> = { ...VALUE, k: 0 };
const KNIGHT = [[-2,-1],[-2,1],[-1,-2],[-1,2],[1,-2],[1,2],[2,-1],[2,1]];
const KING = [[-1,-1],[-1,0],[-1,1],[0,-1],[0,1],[1,-1],[1,0],[1,1]];
const BISHOP = [[-1,-1],[-1,1],[1,-1],[1,1]];
const ROOK = [[-1,0],[1,0],[0,-1],[0,1]];
const QUEEN = [...BISHOP, ...ROOK];

const at = (row: number, col: number) => row * 8 + col;
const rc = (square: number) => [Math.floor(square / 8), square % 8] as const;
const inside = (row: number, col: number) => row >= 0 && row < 8 && col >= 0 && col < 8;

export function createGame(): Game {
  const board: Board = Array(64).fill(null);
  for (let col = 0; col < 8; col += 1) {
    board[at(0, col)] = { color: "black", kind: BACK[col] };
    board[at(1, col)] = { color: "black", kind: "p" };
    board[at(6, col)] = { color: "white", kind: "p" };
    board[at(7, col)] = { color: "white", kind: BACK[col] };
  }
  return { board, turn: "white", history: [], whiteMoves: 0, capturedByWhite: 0, capturedByBlack: 0, winner: null, ended: false, evaluatedLeaves: 0 };
}

export function squareName(square: number) {
  const [row, col] = rc(square);
  return `${"abcdefgh"[col]}${8 - row}`;
}

export function squareIndex(name: string) {
  if (!/^[a-h][1-8]$/i.test(name)) return -1;
  const col = name.toLowerCase().charCodeAt(0) - 97;
  return at(8 - Number(name[1]), col);
}

function rayMoves(board: Board, from: number, color: Color, directions: number[][]) {
  const moves: Move[] = [];
  const [row, col] = rc(from);
  for (const [dr, dc] of directions) {
    for (let step = 1; step < 8; step += 1) {
      const r = row + dr * step;
      const c = col + dc * step;
      if (!inside(r, c)) break;
      const to = at(r, c);
      const target = board[to];
      if (!target) moves.push({ from, to });
      else {
        if (target.color !== color) moves.push({ from, to, capture: target });
        break;
      }
    }
  }
  return moves;
}

export function movesFrom(board: Board, from: number): Move[] {
  const piece = board[from];
  if (!piece) return [];
  const [row, col] = rc(from);
  if (piece.kind === "p") {
    const direction = piece.color === "white" ? -1 : 1;
    const startRow = piece.color === "white" ? 6 : 1;
    const moves: Move[] = [];
    if (inside(row + direction, col) && !board[at(row + direction, col)]) {
      moves.push({ from, to: at(row + direction, col) });
      if (row === startRow && !board[at(row + direction * 2, col)]) moves.push({ from, to: at(row + direction * 2, col) });
    }
    for (const dc of [-1, 1]) {
      if (!inside(row + direction, col + dc)) continue;
      const to = at(row + direction, col + dc);
      const target = board[to];
      if (target && target.color !== piece.color) moves.push({ from, to, capture: target });
    }
    return moves;
  }
  if (piece.kind === "n" || piece.kind === "k") {
    const offsets = piece.kind === "n" ? KNIGHT : KING;
    return offsets.flatMap(([dr, dc]) => {
      const r = row + dr;
      const c = col + dc;
      if (!inside(r, c)) return [];
      const to = at(r, c);
      const target = board[to];
      return !target || target.color !== piece.color ? [{ from, to, capture: target ?? undefined }] : [];
    });
  }
  if (piece.kind === "b") return rayMoves(board, from, piece.color, BISHOP);
  if (piece.kind === "r") return rayMoves(board, from, piece.color, ROOK);
  return rayMoves(board, from, piece.color, QUEEN);
}

export function allMoves(board: Board, color: Color) {
  return board
    .flatMap((piece, index) => piece?.color === color ? movesFrom(board, index) : [])
    .sort((a, b) => a.from - b.from || a.to - b.to);
}

function hasAnyMove(board: Board, color: Color) {
  return board.some((piece, index) => piece?.color === color && movesFrom(board, index).length > 0);
}

function apply(board: Board, move: Move) {
  const next = board.slice();
  next[move.to] = next[move.from];
  next[move.from] = null;
  return next;
}

function evaluate(board: Board, color: Color) {
  return board.reduce((score, piece) => piece ? score + (piece.color === color ? VALUE[piece.kind] : -VALUE[piece.kind]) : score, 0);
}

export function makeMove(game: Game, move: Move): Game {
  if (game.ended) return game;
  const legal = movesFrom(game.board, move.from).find((candidate) => candidate.to === move.to);
  const piece = game.board[move.from];
  if (!legal || !piece || piece.color !== game.turn) return game;
  const capture = legal.capture;
  const board = apply(game.board, legal);
  const winner = capture?.kind === "k" ? piece.color : null;
  const whiteMoves = game.whiteMoves + (piece.color === "white" ? 1 : 0);
  const nextTurn = piece.color === "white" ? "black" : "white";
  const noMoves = !hasAnyMove(board, nextTurn);
  const turnLimit = piece.color === "black" && whiteMoves >= 8;
  return {
    ...game,
    board,
    turn: nextTurn,
    history: [...game.history, { ...legal, capture: capture ?? undefined }],
    whiteMoves,
    capturedByWhite: game.capturedByWhite + (piece.color === "white" && capture ? SCORE_VALUE[capture.kind] : 0),
    capturedByBlack: game.capturedByBlack + (piece.color === "black" && capture ? SCORE_VALUE[capture.kind] : 0),
    winner,
    ended: Boolean(winner || noMoves || turnLimit),
  };
}

export function chooseReply(game: Game, leafCap = 20_000) {
  const candidates = allMoves(game.board, "black");
  let best = candidates[0] ?? null;
  let bestScore = -Infinity;
  let leaves = 0;
  for (const move of candidates) {
    const after = apply(game.board, move);
    let worstReply = Infinity;
    const replies = allMoves(after, "white");
    if (!replies.length) worstReply = evaluate(after, "black");
    for (const reply of replies) {
      if (leaves >= leafCap) break;
      leaves += 1;
      worstReply = Math.min(worstReply, evaluate(apply(after, reply), "black"));
    }
    if (worstReply > bestScore) {
      bestScore = worstReply;
      best = move;
    }
    if (leaves >= leafCap) break;
  }
  return { move: best, leaves };
}

export function playReply(game: Game) {
  if (game.ended || game.turn !== "black") return game;
  const { move, leaves } = chooseReply(game);
  return move ? { ...makeMove(game, move), evaluatedLeaves: leaves } : { ...game, ended: true, evaluatedLeaves: leaves };
}

export function resultFor(game: Game) {
  const score = 100 + game.capturedByWhite - game.capturedByBlack + game.whiteMoves * 5;
  const headline = game.winner === "white" ? "You beat 278 bytes." : game.winner === "black" ? "278 bytes beat you." : `You survived ${game.whiteMoves} move${game.whiteMoves === 1 ? "" : "s"}.`;
  return { score, headline };
}
