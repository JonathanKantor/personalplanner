// Workaround for jac 0.37.14 on phones (Expo Go / native builds).
//
// The Jac compiler turns every component `has` field into a call to
// `useJacState(...)` imported from "@jac/runtime". The browser runtime has it,
// but the *native* runtime that Metro uses (jac-src/client_runtime.js) does
// not export it, so every mobUI screen with state crashes on a phone with
// "TypeError: undefined is not a function".
//
// This module re-exports the whole native runtime and adds useJacState, copied
// from the browser runtime (a per-component state cell: `.val` always holds the
// latest value, `.set(v)` updates it and re-renders). scripts/fix_mobile_native.sh
// points Metro's "@jac/runtime" alias at this file.
import { useRef, useSyncExternalStore } from 'react';

export * from '../jac-src/client_runtime.js';

export function useJacState(initial) {
  const ref = useRef(null);
  if (ref.current == null) {
    const cell = { val: initial, version: 0, listeners: [] };
    cell.subscribe = (cb) => {
      cell.listeners.push(cb);
      return () => {
        const idx = cell.listeners.indexOf(cb);
        if (idx > -1) cell.listeners.splice(idx, 1);
      };
    };
    cell.getVersion = () => cell.version;
    cell.set = (v) => {
      if (Object.is(cell.val, v)) return;
      cell.val = v;
      cell.version += 1;
      for (const cb of cell.listeners.slice()) cb();
    };
    ref.current = cell;
  }
  const store = ref.current;
  useSyncExternalStore(store.subscribe, store.getVersion);
  return store;
}
