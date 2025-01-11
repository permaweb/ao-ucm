import Arweave from 'arweave';
import { OrderbookCreateType } from 'helpers/types';

import { aoCreateProcess, aoSend } from '@permaweb/libs';
import { globalLog } from 'helpers/utils';

// Staging Owner
const UCM_OWNER = 'YYSFAsZBLYAMmPijTam-D1jZbCO0vcWLRimdmMnKHyo'
const UCM_PROCESS = '5j0vKImZBXLyOhg5qqs0u0oeL2MwyIRRfY6OtiTKZtk'

export async function createOrderbook(
	args: OrderbookCreateType,
	wallet: any,
	callback: (args: { processing: boolean, success: boolean, message: string }) => void
): Promise<string> {
	const validationError = getOrderbookCreationErrorMessage(args);
	if (validationError) throw new Error(validationError);

	try {
		globalLog('Creating orderbook...')
		callback({ processing: true, success: false, message: 'Creating asset orderbook...' });

		let orderbookId: string | null = null;
		try {
			orderbookId = await aoCreateProcess({
				evalTxId: UCM_PROCESS,
				wallet: wallet
			});
		}
		catch (e: any) {
			throw new Error(e.message ?? 'Error creating orderbook')
		}

		globalLog(`Orderbook ID: ${orderbookId}`);

		globalLog('Sending intitial message...')
		callback({ processing: true, success: false, message: 'Sending initial message...' });

		const ownerEval = await aoSend({
			processId: orderbookId,
			wallet: wallet,
			action: 'Eval',
			data: `Owner = ${UCM_OWNER}`,
			useRawData: true
		});

		globalLog(`Owner Eval: ${ownerEval}`);

		globalLog('Creating gateway lookup...')
		callback({ processing: true, success: false, message: 'Creating gateway lookup...' });

		const lookupTx = await Arweave.init({}).createTransaction({}, 'use_wallet');
		lookupTx.addTag('Asset-Orderbook-Lookup', args.assetId)
		lookupTx.addTag('Asset-Id', args.assetId)
		lookupTx.addTag('Orderbook-Id', orderbookId)
		const lookupResponse = await global.window.arweaveWallet.dispatch(lookupTx);
		
		globalLog(`Gateway Lookup Response: ${lookupResponse.id}`);

		callback({ processing: false, success: true, message: 'Orderbook created' });

		return orderbookId;
	}
	catch (e: any) {
		const errorMessage = e.message ?? 'Error creating orderbook';
		callback({ processing: false, success: false, message: errorMessage });
		throw new Error(errorMessage);
	}
}

function getOrderbookCreationErrorMessage(args: OrderbookCreateType): string | null {
	if (typeof args !== 'object' || args === null) return 'The provided arguments are invalid or empty.';
	if (typeof args.assetId !== 'string' || args.assetId.trim() === '') return 'Asset ID is required';
	return null;
}