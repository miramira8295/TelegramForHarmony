import { getTdClient } from '../tdkit/Globals';
import { TdObject, TdRequest } from '../tdkit/TdTypes';

// Proxy management. All of this is real TDLib state: the connection actually
// moves through the enabled proxy.

export const PROXY_SOCKS5: string = 'proxyTypeSocks5';
export const PROXY_MTPROTO: string = 'proxyTypeMtproto';
export const PROXY_HTTP: string = 'proxyTypeHttp';

export interface ProxyEntry {
  id: number;
  server: string;
  port: number;
  type: string;       // one of the PROXY_* constants
  username: string;
  password: string;
  secret: string;     // MTProto only
  isEnabled: boolean;
}

export function proxyTypeLabel(type: string): string {
  if (type === PROXY_MTPROTO) {
    return 'MTProto';
  }
  if (type === PROXY_HTTP) {
    return 'HTTP';
  }
  return 'SOCKS5';
}

function toProxyObject(e: ProxyEntry): TdObject {
  const type: TdObject = { '@type': e.type };
  if (e.type === PROXY_MTPROTO) {
    type['secret'] = e.secret;
  } else {
    type['username'] = e.username;
    type['password'] = e.password;
    if (e.type === PROXY_HTTP) {
      type['http_only'] = false;
    }
  }
  const proxy: TdObject = { '@type': 'proxy' };
  proxy['server'] = e.server;
  proxy['port'] = e.port;
  proxy['type'] = type;
  return proxy;
}

function fromAddedProxy(a: TdObject): ProxyEntry {
  const p = (a['proxy'] as TdObject | undefined) ?? {} as TdObject;
  const t = (p['type'] as TdObject | undefined) ?? {} as TdObject;
  return {
    id: (a['id'] as number | undefined) ?? 0,
    server: (p['server'] as string | undefined) ?? '',
    port: (p['port'] as number | undefined) ?? 0,
    type: (t['@type'] as string | undefined) ?? PROXY_SOCKS5,
    username: (t['username'] as string | undefined) ?? '',
    password: (t['password'] as string | undefined) ?? '',
    secret: (t['secret'] as string | undefined) ?? '',
    isEnabled: (a['is_enabled'] as boolean | undefined) ?? false
  };
}

export async function listProxies(): Promise<ProxyEntry[]> {
  const res = await getTdClient().send({ '@type': 'getProxies' } as TdRequest);
  const list = (res['proxies'] as TdObject[] | undefined) ?? [];
  return list.map((a: TdObject): ProxyEntry => fromAddedProxy(a));
}

export async function addProxy(e: ProxyEntry, enable: boolean): Promise<void> {
  const req: TdRequest = { '@type': 'addProxy' };
  req['proxy'] = toProxyObject(e);
  req['enable'] = enable;
  req['comment'] = '';
  await getTdClient().send(req);
}

export async function enableProxy(id: number): Promise<void> {
  const req: TdRequest = { '@type': 'enableProxy' };
  req['proxy_id'] = id;
  await getTdClient().send(req);
}

export async function disableProxy(): Promise<void> {
  await getTdClient().send({ '@type': 'disableProxy' } as TdRequest);
}

export async function removeProxy(id: number): Promise<void> {
  const req: TdRequest = { '@type': 'removeProxy' };
  req['proxy_id'] = id;
  await getTdClient().send(req);
}

// Round-trip time in seconds, or -1 if the proxy is unreachable.
export async function pingProxy(e: ProxyEntry): Promise<number> {
  const req: TdRequest = { '@type': 'pingProxy' };
  req['proxy'] = toProxyObject(e);
  try {
    const res = await getTdClient().send(req);
    return (res['seconds'] as number | undefined) ?? -1;
  } catch (err) {
    return -1;
  }
}
