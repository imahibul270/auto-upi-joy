declare module "cloudflare:sockets" {
  export function connect(address: { hostname: string; port: number }, options?: Record<string, unknown>): any;
}
