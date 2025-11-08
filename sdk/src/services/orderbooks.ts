import { DependenciesType, OrderbookCreateType } from 'helpers/types';

import Permaweb from '@permaweb/libs';
import { globalLog } from 'helpers/utils';

const UCM_ORDERBOOK_PROCESS = 'tv0t200SL1gYKAMCmfSh_YZ9wY9cGTIJTqn-MgbNOjs';
const UCM_ACTIVITY_PROCESS = 'awLQE8Nsy1kdH-g-JuU2Mqd37Ol9TacIHgeWFPDvbn4';

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
			evalTxId: UCM_ORDERBOOK_PROCESS,
			tags: [
				{ name: 'UCM-Process', value: 'Orderbook' },
				{ name: 'Asset-ID', value: args.assetId },
			]
		});
		globalLog(`Orderbook ID: ${orderbookId}`);

		globalLog('Creating activity process...');
		callback({ processing: true, success: false, message: 'Creating activity process...' });
		const activityId = await permaweb.createProcess({
			evalTxId: UCM_ACTIVITY_PROCESS,
			tags: [{ name: 'UCM-Process', value: 'Asset-Activity' }]
		});
		globalLog(`Orderbook Activity ID: ${activityId}`);

		globalLog('Setting orderbook in activity...')
		callback({ processing: true, success: false, message: 'Setting orderbook in activity...' });
		const activityUcmEval = await permaweb.sendMessage({
			processId: activityId,
			action: 'Eval',
			data: `UCM = '${orderbookId}'`,
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

		if (args.collectionId) {
			globalLog('Setting orderbook / activity in collection activity...');
			callback({ processing: true, success: false, message: 'Setting orderbook in collection activity...' });
			const activityCollectionEval = await permaweb.sendMessage({
				processId: activityId,
				action: 'Eval',
				data: `CollectionId = '${args.collectionId}'`,
				useRawData: true
			});
			const collectionActivityEval = await permaweb.sendMessage({
				processId: args.collectionId,
				action: 'Update-Collection-Activity',
				tags: [
					{ name: 'ActivityId', value: activityId },
					{ name: 'UpdateType', value: 'Add' },
				]
			});
			globalLog(`Activity Collection Eval: ${activityCollectionEval}`);
			globalLog(`Collection Activity Eval: ${collectionActivityEval}`);
		}

		if (args.writeToAsset) {
			globalLog('Adding orderbook to asset...');
			callback({ processing: true, success: false, message: 'Adding orderbook to asset...' });
			const assetEval = await permaweb.sendMessage({
				processId: args.assetId,
				action: 'Eval',
				data: assetOrderbookEval(orderbookId),
				useRawData: true
			});

			globalLog(`Asset Eval: ${assetEval}`);
		}

		callback({ processing: false, success: true, message: 'Orderbook created!' });

		return orderbookId;
	}
	catch (e: any) {
		const errorMessage = e.message ?? 'Error creating orderbook';
		callback({ processing: false, success: false, message: errorMessage });
		throw new Error(errorMessage);
	}
}

const assetOrderbookEval = (orderbookId: string) => {
	return `
		local json = require('json')

		if Metadata then
			Metadata.OrderbookId = '${orderbookId}'
		else
			Metadata = {}
			Metadata.OrderbookId = '${orderbookId}'
		end

		Handlers.remove('Info')
		Handlers.add('Info', Handlers.utils.hasMatchingTag('Action', 'Info'), function(msg)
			local name = Token and Token.Name or Name
			local ticker = Token and Token.Ticker or Ticker
			local denomination = Token and Token.Denomination or Denomination
			local transferable = Token and Token.Transferable or Transferable
			local orderbookId = Token and Token.OrderbookId or OrderbookId
			local creator = Token and Token.Creator or Creator
			local balances = Token and Token.Balances or Balances
			local totalSupply = Token and Token.TotalSupply or TotalSupply

			local response = {
				Name = name,
				Ticker = ticker,
				Denomination = tostring(denomination),
				Transferable = transferable or nil,
				Data = json.encode({
					Name = name,
					Ticker = ticker,
					Denomination = tostring(denomination),
					Balances = balances,
					TotalSupply = TotalSupply,
					Transferable = transferable,
					Creator = creator,
					Metadata = Metadata,
					AuthUsers = AuthUsers or {},
        			IndexRecipients = IndexRecipients or {},
					DateCreated = tostring(DateCreated),
					LastUpdate = tostring(LastUpdate)
				})
			}

			if msg.reply then
				msg.reply(response)
			else
				response.Target = msg.From
				Send(response)
			end
		end)
	`;
}

function getOrderbookCreationErrorMessage(args: OrderbookCreateType): string | null {
	if (typeof args !== 'object' || args === null) return 'The provided arguments are invalid or empty.';
	if (typeof args.assetId !== 'string' || args.assetId.trim() === '') return 'Asset ID is required';
	return null;
}