import AoLoader from '@permaweb/ao-loader';
import {
  AOS_WASM,
  AO_LOADER_HANDLER_ENV,
  AO_LOADER_OPTIONS,
  DEFAULT_HANDLE_OPTIONS,
  BUNDLED_MARKETPLACE_SOURCE_CODE,
} from './constants';


/**
 * Loads the aos wasm binary and returns the handle function with program memory
 * 
 * @param {string} lua - The lua code to load into the aos
 * @param {any} wasm - The wasm module to load
 * @param {any} options - The options to pass to the aos loader
 * @param {any} handlerEnv - The handler environment to pass to the aos loader
 * 
 * @returns {Promise<{handle: Function, memory: WebAssembly.Memory}>}
 */
export async function createAosLoader({
	lua,
	wasm = AOS_WASM,
	options = AO_LOADER_OPTIONS,
	handlerEnv = AO_LOADER_HANDLER_ENV
}: {
	lua: string, 
	wasm?: any, 
	options?: any, 
	handlerEnv?: any}) {
	console.log('creating aos loader');
  const handle = await AoLoader(wasm, options);
  const evalRes = await handle(
    null,
    {
      ...DEFAULT_HANDLE_OPTIONS,
      Tags: [
        { name: 'Action', value: 'Eval' },
        { name: 'Module', value: ''.padEnd(43, '1') },
      ],
      Data: lua,
    },
    handlerEnv,
  );
 if (evalRes.Error) {
	throw new Error(`Error loading aos: \n\n${evalRes.Error}`);
 }

  return {
    handle,
    memory: evalRes.Memory,
  };
}