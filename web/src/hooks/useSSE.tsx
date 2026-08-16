import { createContext, useContext, useEffect, useEffectEvent } from "react";

export interface SSEEvent {
  command: string;
  source: string;
  entityType: string | null;
  operation: string | null;
  entityId: number | null;
  clientId: string | null;
}

export type Listener = (event: SSEEvent) => void;

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
