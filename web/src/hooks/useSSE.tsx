import { createContext, useContext, useEffect, useEffectEvent } from "react";

export interface SSEEvent {
  command: string;
  source: string;
  entityType: string | null;
  operation: string | null;
  entityId: number | null;
  oldName: string | null;
  newName: string | null;
  clientId: string | null;
}

export type Listener = (event: SSEEvent) => void;

/**
 * The new name, if this event renamed the entity named `currentName`.
 *
 * Use the structured `oldName`/`newName` the server supplies — parsing
 * `command` cannot work, because the reference in a rename command is an ID in
 * some grammars (`skill rename 3 pastry`) and a name in others
 * (`user rename alice alicia`).
 */
export function renamedTo(event: SSEEvent, currentName: string): string | null {
  if (event.operation !== "rename" || !event.oldName || !event.newName) {
    return null;
  }
  return event.oldName.toLowerCase() === currentName.toLowerCase()
    ? event.newName
    : null;
}

export interface SSEContextValue {
  subscribe: (entityType: string, listener: Listener) => () => void;
  subscribeAll: (listener: Listener) => () => void;
}

export const SSEContext = createContext<SSEContextValue | null>(null);

export function useEntityEvents(entityType: string, callback: Listener) {
  const ctx = useContext(SSEContext);
  const onEvent = useEffectEvent(callback);

  useEffect(() => {
    if (!ctx) return;
    return ctx.subscribe(entityType, (event) => onEvent(event));
  }, [ctx, entityType]);
}

export function useAllEvents(callback: Listener) {
  const ctx = useContext(SSEContext);
  const onEvent = useEffectEvent(callback);

  useEffect(() => {
    if (!ctx) return;
    return ctx.subscribeAll((event) => onEvent(event));
  }, [ctx]);
}
