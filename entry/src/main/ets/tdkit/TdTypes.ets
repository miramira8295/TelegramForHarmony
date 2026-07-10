export type TdObject = Record<string, Object>;

export interface TdRequest extends Record<string, Object> {
  '@type': string;
}

export class TdError extends Error {
  code: number;

  constructor(code: number, message: string) {
    super(message);
    this.code = code;
  }
}

export interface TdBridge {
  init: (onReceive: (json: string) => void) => void;
  send: (json: string) => void;
}
