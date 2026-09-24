import { useState, type FormEvent } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Shuffle, Star, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { supabase } from "@/integrations/supabase/client";
import { Swal } from "@/lib/swal";
import type { Provider } from "@/lib/gateway";

type UpiItem = { id: string; provider: Provider; upi_id: string; payee_name: string; is_primary: boolean };
type UpiState = { routing: boolean; items: UpiItem[] };

const MESSAGES: Record<string, string> = {
  INVALID_UPI_ID: "Enter a valid UPI ID, for example name@ybl.",
  UPI_LIMIT_REACHED: "You can add up to 10 UPI IDs.",
  UPI_ALREADY_ADDED: "This UPI ID is already added.",
};
const msg = (e: unknown) => {
  const m = e instanceof Error ? e.message : (e as { message?: string })?.message ?? String(e);
  const k = Object.keys(MESSAGES).find((c) => m.includes(c));
  return k ? MESSAGES[k] : m;
};

export function UpiRoutingCard({ provider }: { provider: Provider }) {
  const qc = useQueryClient();
  const { data } = useQuery({
    queryKey: ["upi-ids"],
    queryFn: async () => {
      const { data, error } = await (supabase.rpc as any)("list_upi_ids");
      if (error) throw error;
      return data as UpiState;
    },
  });
  const [upi, setUpi] = useState("");
  const [payee, setPayee] = useState("");
  const [busy, setBusy] = useState(false);
  const items = data?.items ?? [];
  const routing = Boolean(data?.routing);
  const refresh = () => qc.invalidateQueries({ queryKey: ["upi-ids"] });

  async function call(fn: string, args: Record<string, unknown>) {
    const { error } = await (supabase.rpc as any)(fn, args);
    if (error) throw error;
    await refresh();
  }

  async function add(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    try {
      await call("add_upi_id", { _upi_id: upi, _payee_name: payee, _provider: provider });
      setUpi(""); setPayee("");
    } catch (err) {
      void Swal.fire({ icon: "error", title: "Could not add", text: msg(err) });
    } finally { setBusy(false); }
  }

  const run = (fn: string, args: Record<string, unknown>) =>
    call(fn, args).catch((err) => Swal.fire({ icon: "error", title: "Failed", text: msg(err) }));

  return (
    <section className="console-card reveal-delay-3" data-reveal>
      <div className="console-card-head">
        <h3>UPI IDs &amp; routing</h3>
        <small>{items.length}/10 added</small>
      </div>

      <label className="upi-route-toggle">
        <input type="checkbox" checked={routing} onChange={(e) => run("set_upi_routing", { _enabled: e.target.checked })} />
        <span className="upi-route-switch"><i /></span>
        <span><Shuffle /> Auto routing {routing ? "ON — each QR uses a random UPI ID" : "OFF — QR uses the primary UPI ID"}</span>
      </label>

      <form className="upi-route-form" onSubmit={add}>
        <Input value={upi} onChange={(e) => setUpi(e.target.value)} placeholder="xyz@ybl" required disabled={items.length >= 10} />
        <Input value={payee} onChange={(e) => setPayee(e.target.value)} placeholder="Payee name (optional)" disabled={items.length >= 10} />
        <Button type="submit" disabled={busy || items.length >= 10}>{busy ? "Adding…" : "Add UPI"}</Button>
      </form>

      <div className="console-conn-list">
        {items.length === 0 ? <p className="upi-route-empty">No extra UPI IDs yet. Your saved UPI ID above is used.</p> : null}
        {items.map((item) => (
          <div key={item.id} className="console-conn-row">
            <span className="console-conn-name">{item.upi_id}</span>
            <span className="console-conn-upi">{item.payee_name || "—"}</span>
            <span>
              {item.is_primary ? (
                <span className="console-conn-badge is-on"><i />Primary</span>
              ) : (
                <Button type="button" variant="outline" size="sm" disabled={routing} onClick={() => run("set_primary_upi", { _id: item.id })}>
                  <Star />Set primary
                </Button>
              )}
            </span>
            <Button type="button" variant="outline" size="sm" onClick={() => run("remove_upi_id", { _id: item.id })}>
              <Trash2 />
            </Button>
          </div>
        ))}
      </div>
    </section>
  );
}
