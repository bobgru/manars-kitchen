import { createContext, useContext, useEffect, useRef, useCallback, type ReactNode } from "react";

export interface SSEEvent {
  command: string;
  source: string;
  entityType: string | null;
  operation: string | null;
  entityId: number | null;
  clientId: string | null;
}

type Listener = (event: SSEEvent) => void;

interface SSEContextValue {
  subscribe: (entityType: string, listener: Listener) => () => void;
  subscribeAll: (listener: Listener) => () => void;
}

const SSEContext = createContext<SSEContextValue | null>(null);

export function SSEProvider({ children }: { children: ReactNode }) {
  const listenersRef = useRef<Map<string, Set<Listener>>>(new Map());
  const allListenersRef = useRef<Set<Listener>>(new Set());

  useEffect(() => {
    const token = sessionStorage.getItem("token");
    if (!token) return;

    const es = new EventSource(`/api/events?token=${token}`);
    es.onmessage = (msg) => {
      try {
        const data: SSEEvent = JSON.parse(msg.data);
        // Dispatch to entity-specific listeners
        if (data.entityType) {
          const listeners = listenersRef.current.get(data.entityType);
          if (listeners) {
            for (const fn of listeners) fn(data);
          }
        }
        // Dispatch to all-events listeners
        for (const fn of allListenersRef.current) fn(data);
      } catch {
        // ignore malformed
      }
    };

    return () => es.close();
  }, []);

  const subscribeFn = useCallback((entityType: string, listener: Listener) => {
    if (!listenersRef.current.has(entityType)) {
      listenersRef.current.set(entityType, new Set());
    }
    listenersRef.current.get(entityType)!.add(listener);
    return () => {
      const set = listenersRef.current.get(entityType);
      if (set) {
        set.delete(listener);
        if (set.size === 0) listenersRef.current.delete(entityType);
      }
    };
  }, []);

  const subscribeAllFn = useCallback((listener: Listener) => {
    allListenersRef.current.add(listener);
    return () => { allListenersRef.current.delete(listener); };
  }, []);

  return (
    <SSEContext.Provider value={{ subscribe: subscribeFn, subscribeAll: subscribeAllFn }}>
      {children}
    </SSEContext.Provider>
  );
}

export function useEntityEvents(entityType: string, callback: (event: SSEEvent) => void) {
  const ctx = useContext(SSEContext);
  const callbackRef = useRef(callback);
  callbackRef.current = callback;

  useEffect(() => {
    if (!ctx) return;
    return ctx.subscribe(entityType, (event) => callbackRef.current(event));
  }, [ctx, entityType]);
}

export function useAllEvents(callback: (event: SSEEvent) => void) {
  const ctx = useContext(SSEContext);
  const callbackRef = useRef(callback);
  callbackRef.current = callback;

  useEffect(() => {
    if (!ctx) return;
    return ctx.subscribeAll((event) => callbackRef.current(event));
  }, [ctx]);
}
