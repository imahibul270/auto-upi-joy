import { useCallback, useEffect, useMemo, useState } from "react";
import { Bell, BellRing, Sparkles, X } from "lucide-react";
import type { User } from "@supabase/supabase-js";
import { useQrQuota } from "@/lib/quota";
import { buildPlanNotifications, relativeTime } from "@/lib/plan-notifications";

function storageKey(userId: string) {
  return `autoupi:notif-read:${userId}`;
}

function hiddenKey(userId: string) {
  return `autoupi:notif-hidden:${userId}`;
}

function readList(key: string): string[] {
  try {
    const raw = window.localStorage.getItem(key);
    const parsed = raw ? (JSON.parse(raw) as unknown) : [];
    return Array.isArray(parsed) ? (parsed as string[]) : [];
  } catch {
    return [];
  }
}

function readSeen(userId: string): string[] {
  return readList(storageKey(userId));
}

/** Plan reminder bell: unread count, pulse animation and a slide-in panel. */
export function NotificationBell({ user }: { user: User }) {
  const { data: quota } = useQrQuota();
  const [open, setOpen] = useState(false);
  const [seen, setSeen] = useState<string[]>([]);
  const [now, setNow] = useState(() => new Date());

  useEffect(() => setSeen(readSeen(user.id)), [user.id]);

  // Keeps slots (8:00 / 12:00 / 17:00) appearing without a page reload.
  useEffect(() => {
    const id = window.setInterval(() => setNow(new Date()), 60000);
    return () => window.clearInterval(id);
  }, []);

  const items = useMemo(() => buildPlanNotifications(quota, now), [quota, now]);
  const unread = items.filter((item) => !seen.includes(item.id));

  const markAllSeen = useCallback(() => {
    const ids = Array.from(new Set([...seen, ...items.map((item) => item.id)])).slice(-60);
    setSeen(ids);
    try {
      window.localStorage.setItem(storageKey(user.id), JSON.stringify(ids));
    } catch {
      /* storage unavailable — badge simply comes back next visit */
    }
  }, [items, seen, user.id]);

  function toggle() {
    setOpen((value) => {
      if (!value) markAllSeen();
      return !value;
    });
  }

  useEffect(() => {
    if (!open) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") setOpen(false);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open]);

  return (
    <>
      <button
        type="button"
        className={`console-icon-btn notif-btn${unread.length ? " has-unread" : ""}`}
        aria-label={unread.length ? `${unread.length} notifications` : "Notifications"}
        onClick={toggle}
      >
        {unread.length ? <BellRing /> : <Bell />}
        {unread.length ? <span className="notif-count">{unread.length}</span> : null}
      </button>

      {open ? (
        <button type="button" className="notif-scrim" aria-label="Close notifications" onClick={() => setOpen(false)} />
      ) : null}

      <aside className={`notif-panel${open ? " is-open" : ""}`} aria-hidden={!open}>
        <header className="notif-panel-head">
          <strong>Notifications</strong>
          <button type="button" className="notif-close" aria-label="Close" onClick={() => setOpen(false)}>
            <X />
          </button>
        </header>
        <div className="notif-list">
          {items.length === 0 ? (
            <p className="notif-empty">You are all caught up.</p>
          ) : (
            items.map((item) => (
              <article key={item.id} className={`notif-item notif-${item.kind}`}>
                <span className="notif-icon"><Sparkles /></span>
                <div>
                  <strong>{item.title}</strong>
                  <p>{item.body}</p>
                  <div className="notif-item-foot">
                    <a href="/plan" className="notif-action">{item.action}</a>
                    <em>{relativeTime(item.at, now)}</em>
                  </div>
                </div>
              </article>
            ))
          )}
        </div>
      </aside>
    </>
  );
}
