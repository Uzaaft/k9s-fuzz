// Bombadil specification for k9s.
//
//   kind create cluster --name fuzz
//   bombadil terminal test --specification spec.ts --time-limit 5m k9s --readonly
//
// --readonly disables shell, edit, delete, scale, etc., so the fuzzer can't
// leave the TUI or mutate the cluster.
import { always, eventually } from "@antithesishq/bombadil";
import { CharSet } from "@antithesishq/bombadil/actions";
import {
  type ActionTemplate,
  extract,
  weighted,
} from "@antithesishq/bombadil/terminal";
import {
  CharSets,
  typeFromSet,
} from "@antithesishq/bombadil/terminal/defaults/actions";
export {
  exitSuccess,
  noReplacementChars,
} from "@antithesishq/bombadil/terminal/defaults/properties";

const screen = extract((state) => {
  const rows = [];
  for (let i = 0; i < state.grid.size.rows; i++) {
    rows.push(state.grid.rowText(i));
  }
  return rows.join("\n");
});

// Properties

// k9s recovers panics in cmd/root.go, prints "Boom!!" and exits 0, so
// exitSuccess alone misses them. Unrecovered goroutine panics print a trace.
export const noPanic = always(
  () => !/Boom!!|panic: |goroutine \d+ \[/.test(screen.current ?? ""),
);

// The screen may blank during a redraw, but never stays blank.
export const neverStuckBlank = always(
  eventually(() => (screen.current ?? "").trim() !== "").within(5, "seconds"),
);

// Actions

const keys = (...literals: string[]) =>
  typeFromSet(CharSet.fromLiterals(...literals));

const navigate = keys(
  "\x1b[A", "\x1b[B", "\x1b[C", "\x1b[D", // arrows
  "\x1b[5~", "\x1b[6~", // page up/down
  "j", "k", "g", "G",
  "\r", "\x1b", "\t",
);

// Views and toggles that don't mutate anything.
const viewKeys = keys(
  "?", "d", "y", "l", "u", "w", "f", "c", "x", "0", "1", "2",
  "\x01", // Ctrl+A: aliases
  "\x05", // Ctrl+E: toggle header
);

const command = keys(
  ...[
    "pods", "deploy", "svc", "ns", "no", "cm", "secrets", "events",
    "ctx", "pulses", "xray deploy", "crd", "sa", "pv", "pvc", "jobs",
    "bogus",
  ].map((c) => `:${c}\r`),
);

const filter = keys("/kube\r", "/core\r", "/-l app=x\r", "/!system\r", "/\x1b");

const resize: ActionTemplate = {
  Resize: { columns: [20, 200], rows: [5, 60] },
};

export const drive = weighted([
  [40, navigate],
  [20, viewKeys],
  [15, command],
  [10, filter],
  [5, typeFromSet(CharSets.ASCII_PRINTABLE)],
  [2, resize],
]);
