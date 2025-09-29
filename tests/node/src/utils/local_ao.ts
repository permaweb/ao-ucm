import { AOS_WASM, AO_LOADER_HANDLER_ENV, AO_LOADER_OPTIONS, BUNDLED_MARKETPLACE_SOURCE_CODE, DEFAULT_HANDLE_OPTIONS } from "./constants";
import AoLoader from "@permaweb/ao-loader";
import { AOProcess } from "@ar.io/sdk";
import { connect } from "@permaweb/aoconnect";
import { createAosLoader } from "utils";



export type AoClient = Awaited<ReturnType<typeof connect>>;

export type HandleFunction = Awaited<ReturnType<typeof AoLoader>>;


/**
 * @description Drop in replacement class representing the return type of the `connect` function from `@permaweb/aoconnect` (@type{AoClient})
 * 
 * This can be initialized and passed to AOProcess.ao
 * 
 * It satisfies our current use of AoClient.dryrun, AoClient.message, and AoClient.result by maintaining a `handle` function
 * created with AoLoader, a `resultsCache`, and a txid-like `nonce`.
 * 
 * @example
 * 
 * ```ts
 *  new AOProcess({
      processId: 'ant-'.padEnd(43, '1'),
      ao: (await LocalAO.init({
        wasmModule: TEST_AOS_ANT_WASM,
        aoLoaderOptions: AO_LOADER_OPTIONS,
        handlerEnv: AO_LOADER_HANDLER_ENV,
      })) as any,
    });
 * ```
 */
export class LocalAO implements Partial<AoClient> {
  wasmModule: any;
  handle: HandleFunction;
  currentMemory: ArrayBufferLike | null;
  startMemory: ArrayBufferLike | null;

  handlerEnv: typeof AO_LOADER_HANDLER_ENV;

  nonce: string;
  resultsCache: Map<string, Awaited<ReturnType<AoClient['result']>>> =
    new Map();
  constructor({
    wasmModule,
    handle,
    handlerEnv,
    memory = null,
    nonce = '0'.padStart(43, '0'),
  }: {
    wasmModule: any;
    handle: HandleFunction;
    handlerEnv: typeof AO_LOADER_HANDLER_ENV;
    memory: ArrayBufferLike | null;
    nonce?: string;
  }) {
    this.wasmModule = wasmModule;
    this.currentMemory = memory;
    this.startMemory = memory;
    this.handle = handle;
    this.nonce = nonce;
    this.handlerEnv = handlerEnv;
  }

  static async init({
	lua,
    wasmModule,
    aoLoaderOptions,
    handlerEnv = AO_LOADER_HANDLER_ENV,
    memory = null,
  }: {
    lua: string;
    wasmModule: any;
    aoLoaderOptions: typeof AO_LOADER_OPTIONS;
    handlerEnv?: typeof AO_LOADER_HANDLER_ENV;
    memory?: ArrayBufferLike | null;
  }): Promise<LocalAO> {
    const {handle, memory: startMemory} = await createAosLoader({
		lua,
		wasm: wasmModule,
		options: aoLoaderOptions,
		handlerEnv,
	});

    return new LocalAO({
      wasmModule,
      handlerEnv,
      memory: memory || startMemory,
      handle,
    });
  }

  async reset() {
    this.currentMemory = this.startMemory;
	this.nonce = '0'.padStart(43, '0');
	this.resultsCache.clear();
  }

  async dryrun(
    params: Parameters<AoClient['dryrun']>[0],
    handlerEnvOverrides?: typeof AO_LOADER_HANDLER_ENV,
  ): ReturnType<AoClient['dryrun']> {
    const res = await this.handle(
      this.currentMemory,
      {
        ...DEFAULT_HANDLE_OPTIONS,
        Id: this.nonce,
        Data: params.data || DEFAULT_HANDLE_OPTIONS.Data,
        Tags: params.tags || DEFAULT_HANDLE_OPTIONS.Tags,
        ...params,
      },
      {
        ...AO_LOADER_HANDLER_ENV,
        ...(handlerEnvOverrides ?? {}),
      },
    );
    if (!res) throw new Error('oops');

    delete res.Memory;

    return res;
  }

  async message(
    params: Parameters<AoClient['message']>[0],
    handlerEnvOverrides?: typeof AO_LOADER_HANDLER_ENV,
  ): Promise<string> {
    const newNonce = (parseInt(this.nonce) + 1).toString().padStart(43, '0');

    const res = await this.handle(
      this.currentMemory,
      {
        ...DEFAULT_HANDLE_OPTIONS,
        Id: newNonce,
        Data: params.data || DEFAULT_HANDLE_OPTIONS.Data,
        Tags: params.tags || DEFAULT_HANDLE_OPTIONS.Tags,
      },
      {
        ...AO_LOADER_HANDLER_ENV,
        ...(handlerEnvOverrides ?? {}),
      },
    ).catch((e) => console.error(e));
    if (!res) throw new Error('Error from handle: ' + res);
    const { Memory, ...rest } = res;
    this.currentMemory = Memory;
    this.nonce = newNonce;
    this.resultsCache.set(this.nonce, rest);
    return this.nonce;
  }

  async result(
    params: Parameters<AoClient['result']>[0],
  ): ReturnType<AoClient['result']> {
    const res = this.resultsCache.get(params.message);
    if (!res) throw new Error('Message does exist');
    return res;
  }

}

export async function createLocalProcess({
  processId = 'process-'.padEnd(43, '0'),
  lua = BUNDLED_MARKETPLACE_SOURCE_CODE,
  wasmModule = AOS_WASM,
  aoLoaderOptions = AO_LOADER_OPTIONS,
  handlerEnv = AO_LOADER_HANDLER_ENV,
} = {}) {
  return new AOProcess({
    processId,
    ao: (await LocalAO.init({
      lua,
      wasmModule,
      aoLoaderOptions,
      handlerEnv,
    })) as any,
  });
}
