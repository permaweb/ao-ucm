import { DependenciesType, OrderbookCreateType } from 'helpers/types';

import Permaweb from '@permaweb/libs';
import { globalLog } from 'helpers/utils';

const UCM_OWNER = 'YYSFAsZBLYAMmPijTam-D1jZbCO0vcWLRimdmMnKHyo';
const UCM_ORDERBOOK_PROCESS = 'NqGfqIQzHQ-8_6mnBme_hdgqSVCMsBDBw1xTe5zky6s'; // Orderbook src
const UCM_ACTIVITY_PROCESS = 'bD_aszjdemv1qd_GibjO8q2n273VKjApSVGXR1sQ_RU'; // Activity src

export async function createOrderbook(
	deps: DependenciesType,
	args: OrderbookCreateType,
	callback: (args: { processing: boolean, success: boolean, message: string }) => void
): Promise<string> {
	const validationError = getOrderbookCreationErrorMessage(args);
	if (validationError) throw new Error(validationError);

	const permaweb = Permaweb.init(deps);

	let orderbookId: string | null = null;
	try {
		globalLog('Creating orderbook process...');
		callback({ processing: true, success: false, message: 'Creating asset orderbook process...' });
		orderbookId = await permaweb.createProcess({
			evalTxId: UCM_ORDERBOOK_PROCESS
		});
		globalLog(`Orderbook ID: ${orderbookId}`);

		globalLog('Creating activity process...');
		callback({ processing: true, success: false, message: 'Creating activity process...' });
		const activityId = await permaweb.createProcess({
			evalTxId: UCM_ACTIVITY_PROCESS,
		});
		globalLog(`Orderbook Activity ID: ${activityId}`);

		globalLog('Setting orderbook in activity...')
		callback({ processing: true, success: false, message: 'Setting orderbook in activity...' });
		const activityUcmEval = await permaweb.sendMessage({
			processId: activityId,
			action: 'Eval',
			data: `UCM_ORDERBOOK_PROCESS = '${orderbookId}'`,
			useRawData: true
		});
		globalLog(`Activity UCM Eval: ${activityUcmEval}`);

		globalLog('Setting activity in orderbook...')
		callback({ processing: true, success: false, message: 'Setting activity in orderbook...' });
		const ucmActivityEval = await permaweb.sendMessage({
			processId: orderbookId,
			action: 'Eval',
			data: `ACTIVITY_PROCESS = '${activityId}'`,
			useRawData: true
		});
		globalLog(`UCM Activity Eval: ${ucmActivityEval}`);
		
		// TODO
		if (args.collectionId) {
			globalLog('Setting orderbook in collection activity...')
			callback({ processing: true, success: false, message: 'Setting orderbook in collection activity...' });
			const collectionActivityEval = await permaweb.sendMessage({
				processId: args.collectionId,
				action: 'Update-Collection-Activity',
				tags: [
					{ name: 'OrderbookId', value: orderbookId },
					{ name: 'UpdateType', value: 'Add' },
				]
			});
			globalLog(`Collection Activity Eval: ${collectionActivityEval}`);
		}

		globalLog('Giving orderbook ownership to UCM...')
		callback({ processing: true, success: false, message: 'Giving orderbook ownership to UCM...' });
		const orderbookOwnerEval = await permaweb.sendMessage({
			processId: orderbookId,
			action: 'Eval',
			data: `Owner = '${UCM_OWNER}'`,
			useRawData: true
		});
		globalLog(`Orderbook Owner Eval: ${orderbookOwnerEval}`);
		
		globalLog('Giving activity ownership to UCM...')
		callback({ processing: true, success: false, message: 'Giving activity ownership to UCM...' });
		const activityOwnerEval = await permaweb.sendMessage({
			processId: activityId,
			action: 'Eval',
			data: `Owner = '${UCM_OWNER}'`,
			useRawData: true
		});
		globalLog(`Activity Owner Eval: ${activityOwnerEval}`);

		globalLog('Adding orderbook to asset...')
		callback({ processing: true, success: false, message: 'Adding orderbook to asset...' });
		const assetEval = await permaweb.sendMessage({
			processId: args.assetId,
			action: 'Eval',
			data: assetOrderbookEval(orderbookId),
			useRawData: true
		});

		globalLog(`Asset Eval: ${assetEval}`);
		callback({ processing: false, success: true, message: 'Orderbook created!' });

		return orderbookId;
	}
	catch (e: any) {
		const errorMessage = e.message ?? 'Error creating orderbook';
		callback({ processing: false, success: false, message: errorMessage });
		throw new Error(errorMessage);
	}
}

const assetOrderbookEval = (orderbookId: string) => `local json = require('json'); OrderbookId = '${orderbookId}'; Handlers.remove('Info'); Handlers.add('Info', Handlers.utils.hasMatchingTag('Action', 'Info'), function(msg) ao.send({ Target = msg.From, Name = Name, Ticker = Ticker, Denomination = tostring(Denomination), Transferable = Transferable or nil, OrderbookId = OrderbookId or nil, Data = json.encode({ Name = Name, Ticker = Ticker, Denomination = tostring(Denomination), Transferable = Transferable or nil, OrderbookId = OrderbookId or nil, Balances = Balances }) }); end);`;
// const assetOrderbookEval = (orderbookId: string) => {
// 	return `
// 		local json = require('json')
// 		OrderbookId = '${orderbookId}'
// 		Handlers.remove('Info')
// 		Handlers.add('Info', Handlers.utils.hasMatchingTag('Action', 'Info'), function(msg)
// 			ao.send({
// 				Target = msg.From,
// 				Name = Name,
// 				Ticker = Ticker,
// 				Denomination = tostring(Denomination),
// 				Transferable = Transferable or nil,
// 				OrderbookId = OrderbookId or nil,
// 				Data = json.encode({
// 					Name = Name,
// 					Ticker = Ticker,
// 					Denomination = tostring(Denomination),
// 					Transferable = Transferable or nil,
// 					OrderbookId = OrderbookId or nil,
// 					Balances = Balances
// 				})
// 			})
// 		end)
// 	`;
// }

function getOrderbookCreationErrorMessage(args: OrderbookCreateType): string | null {
	if (typeof args !== 'object' || args === null) return 'The provided arguments are invalid or empty.';
	if (typeof args.assetId !== 'string' || args.assetId.trim() === '') return 'Asset ID is required';
	return null;
}