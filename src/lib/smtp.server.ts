// Minimal SMTP client (implicit TLS, port 465) used to send the signup OTP mail.
// Works on the edge runtime (cloudflare sockets) and on Node during dev.
// Server only — never import this from client code.

type Conn = {
  write: (text: string) => Promise<void>;
  read: () => Promise<string | null>;
  close: () => void;
};

async function openTls(hostname: string, port: number): Promise<Conn> {
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

export class SmtpError extends Error {}

const b64 = (value: string) => {
  const bytes = new TextEncoder().encode(value);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
};

/** Sends one plain-text email through the admin mailbox (app password login). */
export async function sendMail(options: {
  host: string;
  port?: number;
  user: string;
  password: string;
  to: string;
  subject: string;
  text: string;
  timeoutMs?: number;
}): Promise<void> {
  const port = options.port ?? 465;
  const deadline = Date.now() + (options.timeoutMs ?? 20_000);
  const conn = await openTls(options.host, port);
  let buffer = "";

  async function readReply(): Promise<string> {
    // SMTP replies end with "<code> " on the last line.
    const done = () => /^\d{3} [^\n]*\r?\n$/m.test(buffer) || /\n\d{3} [^\n]*\r?\n$/.test(buffer);
    while (!done()) {
      if (Date.now() > deadline) throw new SmtpError("SMTP_TIMEOUT");
      const chunk = await conn.read();
      if (chunk === null) throw new SmtpError("SMTP_CONNECTION_CLOSED");
      buffer += chunk;
    }
    const out = buffer;
    buffer = "";
    return out;
  }

  async function step(command: string | null, expect: string[]): Promise<string> {
    if (command !== null) await conn.write(`${command}\r\n`);
    const reply = await readReply();
    const code = reply.trim().split(/\r?\n/).pop()?.slice(0, 3) ?? "";
    if (!expect.includes(code)) throw new SmtpError(`SMTP_${code || "ERROR"}: ${reply.trim().slice(0, 160)}`);
    return reply;
  }

  try {
    await step(null, ["220"]);
    await step(`EHLO autoupi`, ["250"]);
    await step("AUTH LOGIN", ["334"]);
    await step(b64(options.user), ["334"]);
    await step(b64(options.password), ["235"]);
    await step(`MAIL FROM:<${options.user}>`, ["250"]);
    await step(`RCPT TO:<${options.to}>`, ["250", "251"]);
    await step("DATA", ["354"]);

    const body = options.text.replace(/\r?\n/g, "\r\n").replace(/^\./gm, "..");
    const message = [
      `From: AUTO UPI <${options.user}>`,
      `To: <${options.to}>`,
      `Subject: ${options.subject}`,
      "MIME-Version: 1.0",
      'Content-Type: text/plain; charset="utf-8"',
      "Content-Transfer-Encoding: 7bit",
      "",
      body,
      ".",
    ].join("\r\n");
    await conn.write(`${message}\r\n`);
    await step(null, ["250"]);

    try {
      await step("QUIT", ["221"]);
    } catch {
      /* ignore */
    }
  } finally {
    conn.close();
  }
}
