// Tiny IMAP client used to read payment alert emails with an app password.
// Works on the edge runtime (cloudflare sockets) and on Node during dev.
// Server only — never import this from client code.

type Conn = {
  write: (text: string) => Promise<void>;
  read: () => Promise<string | null>;
  close: () => void;
};

async function openTls(hostname: string, port: number): Promise<Conn> {
  // Edge runtime first.
  try {
    const mod: any = await import(/* @vite-ignore */ "cloudflare:sockets");
    const socket = mod.connect({ hostname, port }, { secureTransport: "on", allowHalfOpen: false });
    const reader = socket.readable.getReader();
    const writer = socket.writable.getWriter();
    const decoder = new TextDecoder();
    const encoder = new TextEncoder();
    return {
      write: async (text) => {
        await writer.write(encoder.encode(text));
      },
      read: async () => {
        const { value, done } = await reader.read();
        return done ? null : decoder.decode(value, { stream: true });
      },
      close: () => {
        try {
          void socket.close();
        } catch {
          /* ignore */
        }
      },
    };
  } catch {
    // Node fallback (dev server).
  }

  const tls: any = await import(/* @vite-ignore */ "node:tls");
  const socket: any = await new Promise((resolve, reject) => {
    const s = tls.connect({ host: hostname, port, servername: hostname }, () => resolve(s));
    s.once("error", reject);
  });
  socket.setEncoding("utf8");

  const queue: string[] = [];
  let waiter: ((value: string | null) => void) | null = null;
  let ended = false;

  socket.on("data", (chunk: string) => {
    if (waiter) {
      const w = waiter;
      waiter = null;
      w(chunk);
    } else queue.push(chunk);
  });
  const finish = () => {
    ended = true;
    if (waiter) {
      const w = waiter;
      waiter = null;
      w(null);
    }
  };
  socket.on("end", finish);
  socket.on("close", finish);
  socket.on("error", finish);

  return {
    write: async (text) =>
      new Promise<void>((resolve, reject) => socket.write(text, (e: Error) => (e ? reject(e) : resolve()))),
    read: async () => {
      if (queue.length) return queue.shift()!;
      if (ended) return null;
      return new Promise<string | null>((resolve) => {
        waiter = resolve;
      });
    },
    close: () => {
      try {
        socket.destroy();
      } catch {
        /* ignore */
      }
    },
  };
}

export type ImapMessage = { uid: string; raw: string };

export class ImapError extends Error {}

/**
 * Logs in with an app password and returns the raw source of the newest
 * messages received since `sinceDays` days ago (max `limit` messages).
 */
export async function fetchRecentMessages(options: {
  host: string;
  port?: number;
  user: string;
  password: string;
  sinceDays?: number;
  limit?: number;
  timeoutMs?: number;
  /** Optional sender keyword, e.g. "phonepe" — alerts are found even in a busy inbox. */
  fromFilter?: string;
}): Promise<ImapMessage[]> {
  const { host, user, password } = options;
  const port = options.port ?? 993;
  const limit = options.limit ?? 12;
  const sinceDays = options.sinceDays ?? 1;
  const deadline = Date.now() + (options.timeoutMs ?? 20_000);

  const conn = await openTls(host, port);
  let buffer = "";
  let tagCounter = 0;

  async function pump(): Promise<void> {
    if (Date.now() > deadline) throw new ImapError("IMAP_TIMEOUT");
    const chunk = await conn.read();
    if (chunk === null) throw new ImapError("IMAP_CONNECTION_CLOSED");
    buffer += chunk;
  }

  async function waitFor(test: (buf: string) => boolean): Promise<string> {
    while (!test(buffer)) await pump();
    const out = buffer;
    buffer = "";
    return out;
  }

  async function command(text: string): Promise<string> {
    const tag = `a${++tagCounter}`;
    await conn.write(`${tag} ${text}\r\n`);
    const done = new RegExp(`^${tag} (OK|NO|BAD)`, "m");
    const response = await waitFor((buf) => done.test(buf));
    const status = response.match(done)?.[1];
    if (status !== "OK") {
      const line = response.split(/\r?\n/).find((l) => l.startsWith(`${tag} `)) ?? "";
      throw new ImapError(line.replace(`${tag} `, "") || "IMAP_COMMAND_FAILED");
    }
    return response;
  }

  try {
    await waitFor((buf) => /^\* (OK|PREAUTH)/m.test(buf));

    const esc = (v: string) => v.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
    try {
      await command(`LOGIN "${esc(user)}" "${esc(password)}"`);
    } catch (error) {
      throw new ImapError(`IMAP_LOGIN_FAILED: ${(error as Error).message}`);
    }

    await command("SELECT INBOX");

    const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    const since = new Date(Date.now() - sinceDays * 86_400_000);
    const sinceStr = `${String(since.getUTCDate()).padStart(2, "0")}-${months[since.getUTCMonth()]}-${since.getUTCFullYear()}`;

    async function search(query: string): Promise<string[]> {
      try {
        const res = await command(query);
        const line = res.split(/\r?\n/).find((l) => l.toUpperCase().startsWith("* SEARCH")) ?? "";
        return line.trim().split(/\s+/).slice(2).filter((v) => /^\d+$/.test(v));
      } catch {
        return [];
      }
    }

    // Targeted first: alert emails are found even when the inbox is busy.
    const targeted = options.fromFilter
      ? await search(`UID SEARCH SINCE ${sinceStr} FROM "${options.fromFilter.replace(/"/g, "")}"`)
      : [];
    const all = await search(`UID SEARCH SINCE ${sinceStr}`);
    const merged: string[] = [];
    for (const uid of [...targeted.slice(-limit), ...all.slice(-limit)]) {
      if (!merged.includes(uid)) merged.push(uid);
    }
    const recent = merged.slice(0, limit * 2);

    const messages: ImapMessage[] = [];
    for (const uid of recent) {
      if (Date.now() > deadline) break;
      try {
        const raw = await command(`UID FETCH ${uid} (BODY.PEEK[])`);
        messages.push({ uid, raw });
      } catch {
        // skip unreadable message
      }
    }

    try {
      await command("LOGOUT");
    } catch {
      /* ignore */
    }
    return messages;
  } finally {
    conn.close();
  }
}

function decodeBase64(value: string): string {
  try {
    const bytes = Uint8Array.from(atob(value.replace(/\s+/g, "")), (c) => c.charCodeAt(0));
    return new TextDecoder().decode(bytes);
  } catch {
    return value;
  }
}

function decodeQuotedPrintable(value: string): string {
  const joined = value.replace(/=\r?\n/g, "");
  const bytes: number[] = [];
  for (let i = 0; i < joined.length; i++) {
    if (joined[i] === "=" && /[0-9A-Fa-f]{2}/.test(joined.slice(i + 1, i + 3))) {
      bytes.push(Number.parseInt(joined.slice(i + 1, i + 3), 16));
      i += 2;
    } else bytes.push(joined.charCodeAt(i));
  }
  try {
    return new TextDecoder().decode(Uint8Array.from(bytes));
  } catch {
    return joined;
  }
}

/** Decodes RFC 2047 encoded-words found in Subject / From headers. */
export function decodeHeaderValue(value: string): string {
  return value
    .replace(/=\?([^?]+)\?([BbQq])\?([^?]*)\?=/g, (_m, _cs, enc, text) =>
      String(enc).toUpperCase() === "B" ? decodeBase64(text) : decodeQuotedPrintable(String(text).replace(/_/g, " ")),
    )
    .replace(/\s+/g, " ")
    .trim();
}

/** Splits a raw IMAP FETCH payload into headers plus readable body text. */
export function parseMessage(raw: string): { headers: Record<string, string>; text: string } {
  const start = raw.indexOf("\r\n");
  const body = start >= 0 ? raw.slice(start + 2) : raw;
  const split = body.search(/\r?\n\r?\n/);
  const headerBlock = (split >= 0 ? body.slice(0, split) : body).replace(/\r?\n[ \t]+/g, " ");
  const rest = split >= 0 ? body.slice(split) : "";

  const headers: Record<string, string> = {};
  for (const line of headerBlock.split(/\r?\n/)) {
    const idx = line.indexOf(":");
    if (idx <= 0) continue;
    const key = line.slice(0, idx).trim().toLowerCase();
    if (!headers[key]) headers[key] = decodeHeaderValue(line.slice(idx + 1).trim());
  }

  let text = rest;
  if (/quoted-printable/i.test(raw)) text = decodeQuotedPrintable(text);
  else if (/content-transfer-encoding:\s*base64/i.test(headerBlock)) text = decodeBase64(text);

  text = text
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&#8377;|&rupee;/gi, "₹")
    .replace(/\s+/g, " ")
    .trim();

  return { headers, text };
}
