(function () {
  "use strict";

  var COLS = 80;
  var ROWS = 25;
  var POLL = 300;
  var REPLY_TIMEOUT = 9000;
  var KEY_STAGGER = 140;
  var LUMA_THRESHOLD = 80;
  var LIT_THRESHOLD = 2;

  var FILES = ["a", "b", "c", "d", "e", "f", "g", "h"];
  var MOVE_RE = /^[a-h][1-8][a-h][1-8]$/;

  var START = [
    ["r", "n", "b", "q", "k", "b", "n", "r"],
    ["p", "p", "p", "p", "p", "p", "p", "p"],
    ["", "", "", "", "", "", "", ""],
    ["", "", "", "", "", "", "", ""],
    ["", "", "", "", "", "", "", ""],
    ["", "", "", "", "", "", "", ""],
    ["P", "P", "P", "P", "P", "P", "P", "P"],
    ["R", "N", "B", "Q", "K", "B", "N", "R"]
  ];

  var $ = function (id) { return document.getElementById(id); };

  var gridEl = $("grid");
  var ranksEl = $("ranks");
  var filesEl = $("files");
  var stageEl = $("stage");
  var mount = $("dos");
  var overlay = $("overlay");
  var startBtn = $("start");
  var moveInput = $("move");
  var sendBtn = $("send");
  var stateEl = $("state");

  var ci = null;
  var booting = false;
  var calibrated = false;
  var gameOver = false;
  var waiting = false;

  var glyphs = {};
  var pieceMode = "pieces";
  var selectedSquare = null;
  var beforeMove = "";
  var bootTimer = null;
  var emulatorPromise = null;
  var SYMBOLS = { K: "♔", Q: "♕", R: "♖", B: "♗", N: "♘", P: "♙", k: "♚", q: "♛", r: "♜", b: "♝", n: "♞", p: "♟" };
  var PIECE_NAMES = { k: "king", q: "queen", r: "rook", b: "bishop", n: "knight", p: "pawn" };
  var cells = [];
  var lastBoard = "";
  var shown = cloneBoard(START);
  var lastMove = null;

  var frame = null;
  var frameW = 0;
  var frameH = 0;
  var channels = 4;

  var pollTimer = null;
  var moveTimer = null;

  function cloneBoard(b) {
    var out = new Array(8);
    for (var r = 0; r < 8; r++) out[r] = b[r].slice();
    return out;
  }

  function parseMove(text) {
    return {
      fromC: text.charCodeAt(0) - 97,
      fromR: 8 - (text.charCodeAt(1) - 48),
      toC: text.charCodeAt(2) - 97,
      toR: 8 - (text.charCodeAt(3) - 48)
    };
  }

  function buildGrid() {
    var boardFrag = document.createDocumentFragment();
    var rankFrag = document.createDocumentFragment();
    for (var r = 0; r < 8; r++) {
      cells[r] = new Array(8);
      for (var f = 0; f < 8; f++) {
        var d = document.createElement("button");
        d.type = "button";
        d.tabIndex = r === 7 && f === 4 ? 0 : -1;
        d.dataset.row = r;
        d.dataset.col = f;
        d.addEventListener("click", selectSquare);
        d.className = "sq" + ((r + f) % 2 ? " is-dark" : "");
        boardFrag.appendChild(d);
        cells[r][f] = d;
      }
      var rk = document.createElement("span");
      rk.textContent = String(8 - r);
      rankFrag.appendChild(rk);
    }
    gridEl.appendChild(boardFrag);
    ranksEl.appendChild(rankFrag);

    var fileFrag = document.createDocumentFragment();
    for (var i = 0; i < FILES.length; i++) {
      var s = document.createElement("span");
      s.textContent = FILES[i];
      fileFrag.appendChild(s);
    }
    filesEl.appendChild(fileFrag);

    paint(START);
  }

  function paint(board) {
    var from = lastMove ? lastMove[0] : "";
    var to = lastMove ? lastMove[1] : "";
    for (var r = 0; r < 8; r++) {
      for (var f = 0; f < 8; f++) {
        var ch = board[r][f];
        var el = cells[r][f];
        var dark = (r + f) % 2 ? " is-dark" : "";
        var id = "" + r + f;
        var mark = id === from ? " is-from" : id === to ? " is-to" : "";
        if (ch) {
          el.textContent = pieceMode === "ascii" ? ch : SYMBOLS[ch] || ch;
          el.className = "sq" + (ch === ch.toLowerCase() ? " is-black" : "") + dark + mark;
        } else {
          el.textContent = pieceMode === "ascii" ? "·" : "";
          el.className = "sq is-empty" + dark + mark;
        }
        el.setAttribute("aria-label", FILES[f] + (8 - r) + ": " + (ch ? (ch === ch.toLowerCase() ? "Black " : "White ") + (PIECE_NAMES[ch.toLowerCase()] || ch) : "empty"));
        var isSelected = !!selectedSquare && selectedSquare[0] === r && selectedSquare[1] === f;
        el.classList.toggle("is-selected", isSelected);
        el.setAttribute("aria-pressed", String(isSelected));
      }
    }
  }

  function signature(row, col) {
    var cw = frameW / COLS;
    var chh = frameH / ROWS;
    var x0 = col * cw;
    var y0 = row * chh;
    var sig = "";
    var lit = 0;
    for (var sy = 0; sy < 8; sy++) {
      for (var sx = 0; sx < 6; sx++) {
        var px = Math.round(x0 + (sx + 0.5) * cw / 6);
        var py = Math.round(y0 + (sy + 1) * chh / 10);
        if (px < 0 || py < 0 || px >= frameW || py >= frameH) {
          sig += "0";
          continue;
        }
        var i = (py * frameW + px) * channels;
        var lum = frame[i] * 0.3 + frame[i + 1] * 0.59 + frame[i + 2] * 0.11;
        if (lum > LUMA_THRESHOLD) {
          sig += "1";
          lit++;
        } else {
          sig += "0";
        }
      }
    }
    return { sig: sig, lit: lit };
  }

  function readScreen() {
    if (!frame || !frameW || !frameH) return null;

    var cache = {};
    function at(row, col) {
      var k = row + ":" + col;
      var hit = cache[k];
      if (hit === undefined) {
        hit = signature(row, col);
        cache[k] = hit;
      }
      return hit;
    }
    function filled(row) {
      var list = [];
      for (var c = 0; c < 24; c++) {
        if (at(row, c).lit > LIT_THRESHOLD) list.push(c);
      }
      return list;
    }
    function denseRow(r) {
      var f = filled(r);
      return f.length >= 6 && f[f.length - 1] - f[0] <= 9 ? f : null;
    }

    var baseRow = -1;
    var col0 = 0;
    var spacing = 1;
    for (var r = ROWS - 1; r >= 7; r--) {
      var f = denseRow(r);
      if (!f) continue;
      var sp = denseRow(r - 1) ? 1 : 2;
      var topR = r - 7 * sp;
      if (topR < 0) continue;
      if (!denseRow(topR)) continue;
      if (topR - 1 >= 0 && denseRow(topR - 1)) continue;
      baseRow = r;
      col0 = f[0];
      spacing = sp;
      break;
    }
    if (baseRow < 0) return null;

    var top = baseRow - 7 * spacing;
    if (top < 0) return null;

    var sigs = new Array(8);
    for (var i = 0; i < 8; i++) {
      sigs[i] = new Array(8);
      for (var j = 0; j < 8; j++) {
        sigs[i][j] = at(top + i * spacing, col0 + j);
      }
    }
    return sigs;
  }

  function calibrate(sigs) {
    var i, j;
    for (i = 0; i < 8; i++) {
      for (j = 0; j < 8; j++) {
        var expect = START[i][j];
        var lit = sigs[i][j].lit;
        if (expect === "" && lit > LIT_THRESHOLD) return false;
        if (expect !== "" && lit <= LIT_THRESHOLD) return false;
      }
    }
    var map = {};
    for (i = 0; i < 8; i++) {
      for (j = 0; j < 8; j++) {
        if (START[i][j] !== "") map[sigs[i][j].sig] = START[i][j];
      }
    }
    glyphs = map;
    calibrated = true;
    return true;
  }

  function decode(sigs) {
    var board = new Array(8);
    for (var i = 0; i < 8; i++) {
      board[i] = new Array(8);
      for (var j = 0; j < 8; j++) {
        var s = sigs[i][j];
        board[i][j] = s.lit <= LIT_THRESHOLD ? "" : glyphs[s.sig] || "?";
      }
    }
    return board;
  }

  function hasUnknown(board) {
    for (var r = 0; r < 8; r++) {
      for (var c = 0; c < 8; c++) {
        if (board[r][c] === "?") return true;
      }
    }
    return false;
  }

  function tick() {
    var sigs = readScreen();
    if (!sigs) return;

    if (!calibrated) {
      if (calibrate(sigs)) {
        shown = cloneBoard(START);
        lastMove = null;
        lastBoard = JSON.stringify(START);
        paint(shown);
        clearTimeout(bootTimer);
        overlay.hidden = true;
        startBtn.hidden = true;
        $("restart").hidden = false;
        setState("Your move");
        enableInput();
      }
      return;
    }

    var board = decode(sigs);
    if (hasUnknown(board)) return;

    var key = JSON.stringify(board);
    if (key === lastBoard || (waiting && key === beforeMove)) return;
    lastBoard = key;

    if (waiting) lastMove = diffMove(shown, board);
    shown = cloneBoard(board);
    paint(shown);

    if (waiting) {
      waiting = false;
      clearMoveTimer();
      setState("Your move");
      enableInput();
    }
  }

  function endGame() {
    if (gameOver) return;
    gameOver = true;
    waiting = false;
    clearMoveTimer();
    stopPolling();
    disableInput();
    moveInput.placeholder = "game over";
    setState("No reply received");
    showEndOverlay();
  }

  function showEndOverlay() {
    if (!stageEl) return;
    var el = document.createElement("div");
    el.className = "overlay is-end";

    var title = document.createElement("p");
    var strong = document.createElement("strong");
    strong.textContent = "The engine has stopped replying.";
    title.appendChild(strong);

    var body = document.createElement("p");
    body.textContent = "No reply arrived within nine seconds. The program deliberately stops when no move is generated; invalid chess moves or a slow emulator can also interrupt play. This is not a checkmate verdict.";

    var again = document.createElement("button");
    again.className = "btn";
    again.type = "button";
    again.textContent = "New game";
    again.addEventListener("click", function () { location.reload(); });

    el.appendChild(title);
    el.appendChild(body);
    el.appendChild(again);
    stageEl.appendChild(el);
    again.focus();
  }

  function diffMove(before, after) {
    var emptied = "";
    var filled = "";
    for (var r = 0; r < 8; r++) {
      for (var f = 0; f < 8; f++) {
        if (before[r][f] === after[r][f]) continue;
        var id = "" + r + f;
        if (after[r][f] === "") emptied = id;
        else filled = id;
      }
    }
    return filled ? [emptied, filled] : null;
  }

  function setState(text) {
    stateEl.textContent = text;
  }

  function enableInput() {
    if (gameOver) return;
    moveInput.disabled = false;
    sendBtn.disabled = false;
    moveInput.focus();
  }

  function disableInput() {
    moveInput.disabled = true;
    sendBtn.disabled = true;
  }

  function showError(title, detail) {
    clearTimeout(bootTimer);
    overlay.hidden = false;
    overlay.className = "overlay is-error";
    setState(title);
    booting = false;
    startBtn.disabled = false;
    overlay.textContent = "";
    var p1 = document.createElement("p");
    var strong = document.createElement("strong");
    strong.textContent = title;
    p1.appendChild(strong);
    var p2 = document.createElement("p");
    p2.textContent = detail;
    overlay.appendChild(p1);
    overlay.appendChild(p2);
  }

  function clearMoveTimer() {
    if (moveTimer !== null) {
      clearTimeout(moveTimer);
      moveTimer = null;
    }
  }

  function stopPolling() {
    if (pollTimer !== null) {
      clearInterval(pollTimer);
      pollTimer = null;
    }
  }

  function setSize(w, h) {
    if (w) frameW = w;
    if (h) frameH = h;
  }

  function loadEmulator() {
    if (typeof window.Dos === "function") return Promise.resolve();
    if (emulatorPromise) return emulatorPromise;
    emulatorPromise = new Promise(function (resolve, reject) {
      if (!document.querySelector('link[data-emulator]')) {
        var css = document.createElement("link");
        css.rel = "stylesheet";
        css.href = "jsdos/js-dos.css";
        css.dataset.emulator = "true";
        document.head.insertBefore(css, document.querySelector('link[href="site.css"]'));
      }
      var script = document.createElement("script");
      script.src = "jsdos/js-dos.js";
      script.onload = function () {
        if (typeof window.Dos === "function") resolve();
        else { emulatorPromise = null; reject(new Error("The emulator did not initialize.")); }
      };
      script.onerror = function () {
        emulatorPromise = null;
        script.remove();
        reject(new Error("The emulator could not be downloaded. Check your connection and try Start game again."));
      };
      document.head.appendChild(script);
    });
    return emulatorPromise;
  }

  function boot() {
    if (booting) return;
    booting = true;
    startBtn.disabled = true;
    overlay.hidden = false;
    overlay.className = "overlay";
    overlay.textContent = "Starting the original DOS program…";
    setState("Loading the DOS machine…");
    bootTimer = setTimeout(function () {
      showError("The DOS machine did not start.", "Please reload to try again, or download the COM and run it in DOSBox.");
    }, 30000);

    loadEmulator().then(function () {
      window.Dos(mount, {
        url: "attochess.zip?v=1e395c1e523f",
        theme: "black",
        kiosk: true,
        autoStart: true,
        noCloud: true,
        pathPrefix: "jsdos/emulators/",
        renderAspect: "Fit",
        onEvent: function (event, commandInterface) {
          if (event !== "ci-ready") return;
          ci = commandInterface;
          setState("Reading the DOS board…");
          try { setSize(ci.width(), ci.height()); } catch (e) {}
          ci.events().onFrameSize(setSize);
          ci.events().onFrame(function (rgb, rgba) {
            if (rgb) { frame = rgb; channels = 3; }
            else if (rgba) { frame = rgba; channels = 4; }
            if (!frameW || !frameH) {
              try { setSize(ci.width(), ci.height()); } catch (e) {}
            }
          });
          stopPolling();
          pollTimer = setInterval(tick, POLL);
        }
      });
    }).catch(function (error) {
      showError("The emulator could not start.", error.message || "Please reload to try again.");
    });
  }

  function selectSquare(event) {
    var target = event.currentTarget;
    if (!calibrated || gameOver || waiting) {
      setState(!calibrated ? "Press Start game first" : gameOver ? "Start a new game to play" : "Black is thinking");
      return;
    }
    var r = Number(target.dataset.row);
    var c = Number(target.dataset.col);
    var piece = shown[r][c];
    moveInput.removeAttribute("aria-invalid");
    if (!selectedSquare || (piece && piece === piece.toUpperCase())) {
      if (!piece || piece !== piece.toUpperCase()) { setState("Select one of your White pieces"); return; }
      selectedSquare = [r, c];
      moveInput.value = FILES[c] + (8 - r);
      setState("Select the destination square");
    } else {
      moveInput.value = FILES[selectedSquare[1]] + (8 - selectedSquare[0]) + FILES[c] + (8 - r);
      selectedSquare = null;
      setState("Press Play move to send " + moveInput.value);
      moveInput.focus();
    }
    paint(shown);
  }

  function setPieceMode(mode) {
    pieceMode = mode;
    gridEl.classList.toggle("is-ascii", mode === "ascii");
    $("pieces-view").setAttribute("aria-pressed", String(mode === "pieces"));
    $("ascii-view").setAttribute("aria-pressed", String(mode === "ascii"));
    paint(shown);
  }

  function navigateBoard(event) {
    if (event.type !== "keydown") return;
    var target = event.target;
    var r = Number(target.dataset.row);
    var c = Number(target.dataset.col);
    var nextR = r;
    var nextC = c;
    if (event.key === "ArrowUp") nextR = Math.max(0, r - 1);
    else if (event.key === "ArrowDown") nextR = Math.min(7, r + 1);
    else if (event.key === "ArrowLeft") nextC = Math.max(0, c - 1);
    else if (event.key === "ArrowRight") nextC = Math.min(7, c + 1);
    else if (event.key === "Escape") {
      selectedSquare = null;
      moveInput.value = "";
      paint(shown);
      setState("Your move");
      return;
    } else return;
    event.preventDefault();
    target.tabIndex = -1;
    cells[nextR][nextC].tabIndex = 0;
    cells[nextR][nextC].focus();
  }

  // js-dos keycodes: KBD_a..KBD_z = 65..90, KBD_0..KBD_9 = 48..57
  // (see the keycode table in jsdos/js-dos.js). A move is only [a-h][1-8]{2},
  // so the char code of the uppercased letter, or of the digit, is the keycode.
  function keyCode(ch) {
    return ch.toUpperCase().charCodeAt(0);
  }

  // Feed the move one keystroke at a time. simulateKeyPress() holds a key for
  // only ~16 emulated ms, which is narrow enough that DOSBox's keyboard scan
  // can miss it under real-time frame pacing. Drop one key and every later
  // character shifts into an earlier slot (g1f3 arrives as d3, and so on).
  // So drive an explicit key-down, hold, key-up per character with generous
  // spacing, which gives the program's blocking int 21h/AH=01h read time to
  // consume each keystroke before the next one is sent.
  function typeMove(text) {
    var codes = [];
    for (var i = 0; i < text.length; i++) codes.push(keyCode(text.charAt(i)));

    var i2 = 0;
    (function next() {
      if (!ci || i2 >= codes.length) return;
      var code = codes[i2++];
      ci.sendKeyEvent(code, true);   // key down
      setTimeout(function () {
        if (ci) ci.sendKeyEvent(code, false); // key up
        setTimeout(next, KEY_STAGGER);
      }, KEY_STAGGER);
    })();
  }

  function sendMove() {
    if (!ci || !calibrated || gameOver || waiting) return;

    var text = moveInput.value.trim().toLowerCase();
    if (!MOVE_RE.test(text)) {
      moveInput.setAttribute("aria-invalid", "true");
      setState("Use four coordinates, e.g. e2e4");
      moveInput.select();
      return;
    }
    var parsed = parseMove(text);
    var source = shown[parsed.fromR][parsed.fromC];
    var destination = shown[parsed.toR][parsed.toC];
    if (!source || source !== source.toUpperCase() || (destination && destination === destination.toUpperCase())) {
      moveInput.setAttribute("aria-invalid", "true");
      setState("Move a White piece to an empty or Black square");
      moveInput.select();
      return;
    }
    moveInput.removeAttribute("aria-invalid");
    selectedSquare = null;
    beforeMove = JSON.stringify(shown);
    disableInput();
    waiting = true;

    var mv = parseMove(text);
    var piece = shown[mv.fromR][mv.fromC];
    if (piece) {
      shown[mv.fromR][mv.fromC] = "";
      shown[mv.toR][mv.toC] = piece;
      lastMove = ["" + mv.fromR + mv.fromC, "" + mv.toR + mv.toC];
      lastBoard = JSON.stringify(shown);
      paint(shown);
    }
    setState("Black is thinking");

    typeMove(text);
    moveInput.value = "";

    clearMoveTimer();
    moveTimer = setTimeout(function () {
      moveTimer = null;
      if (waiting) {
        waiting = false;
        endGame();
      }
    }, REPLY_TIMEOUT);
  }

  buildGrid();

  ["keydown", "keyup", "keypress"].forEach(function (type) {
    window.addEventListener(type, function (e) {
      var square = e.target && e.target.closest && e.target.closest(".sq");
      // The DOS machine is offscreen: only typeMove may send it keystrokes.
      // Keep native browser defaults (Tab, Space, copying) without forwarding
      // unrelated page keys into the program's four-character input buffer.
      e.stopImmediatePropagation();
      if (square) navigateBoard(e);
      if (e.target === moveInput && type === "keydown" && e.key === "Enter") {
        e.preventDefault();
        sendMove();
      }
    }, true);
  });

  $("pieces-view").addEventListener("click", function () { setPieceMode("pieces"); });
  $("ascii-view").addEventListener("click", function () { setPieceMode("ascii"); });
  $("restart").addEventListener("click", function () { location.reload(); });
  moveInput.addEventListener("input", function () { moveInput.removeAttribute("aria-invalid"); });
  startBtn.addEventListener("click", boot);
  sendBtn.addEventListener("click", sendMove);
})();
