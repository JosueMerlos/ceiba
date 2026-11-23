import type { BrandingFile } from "@ceiba/api-client";
import { useCallback, useEffect, useRef, useState } from "react";

interface Chosen {
  file: File;
  url: string;
}
type ChosenFiles = Partial<Record<BrandingFile, Chosen>>;

/**
 * Files picked on the edit screen, with a local preview URL each. Every object URL is revoked as soon as it is replaced,
 * removed or the screen goes away, so previews never leak memory.
 */
export function useBrandingFiles() {
  const [chosen, setChosen] = useState<ChosenFiles>({});
  const [removed, setRemoved] = useState<readonly BrandingFile[]>([]);
  // Mirror of `chosen` for cleanup and revocation outside render (state updaters must stay pure).
  const latest = useRef<ChosenFiles>({});

  const commit = useCallback((next: ChosenFiles) => {
    latest.current = next;
    setChosen(next);
  }, []);

  const without = (name: BrandingFile) => {
    const { [name]: previous, ...rest } = latest.current;
    if (previous) URL.revokeObjectURL(previous.url);
    return rest;
  };

  const select = (name: BrandingFile, file: File) => {
    commit({ ...without(name), [name]: { file, url: URL.createObjectURL(file) } });
    setRemoved((current) => current.filter((item) => item !== name));
  };

  const remove = (name: BrandingFile) => {
    commit(without(name));
    setRemoved((current) => (current.includes(name) ? current : [...current, name]));
  };

  const reset = () => {
    for (const entry of Object.values(latest.current)) URL.revokeObjectURL(entry.url);
    commit({});
    setRemoved([]);
  };

  useEffect(
    () => () => {
      for (const entry of Object.values(latest.current)) URL.revokeObjectURL(entry.url);
    },
    [],
  );

  const files: Partial<Record<BrandingFile, File>> = {};
  for (const [name, entry] of Object.entries(chosen)) files[name as BrandingFile] = entry.file;

  return { chosen, files, removed, select, remove, reset };
}
