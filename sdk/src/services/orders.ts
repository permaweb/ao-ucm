import Permaweb from '@permaweb/libs';

import { DependenciesType, OrderCancelType, OrderCreateType } from 'helpers/types';
import { getTagValue, globalLog } from 'helpers/utils';

const MAX_RESULT_RETRIES = 1000;

export async function createOrder(
	deps: DependenciesType,
	args: OrderCreateType,
	callback: (args: { processing: boolean, success: boolean, message: string }) => void
): Promise<string> {
	const validationError = getOrderCreationErrorMessage(args);
	if (validationError) throw new Error(validationError);

	const permaweb = Permaweb.init(deps);

	try {
		const MESSAGE_GROUP_ID = Date.now().toString();

		const tags = [
			{ name: 'Recipient', value: args.orderbookId },
			{ name: 'Quantity', value: args.quantity },
		];

		if (args.creatorId) {
			tags.push({ name: 'Target', value: args.dominantToken },
				{ name: 'ForwardTo', value: args.dominantToken },
				{ name: 'ForwardAction', value: 'Transfer' },
				{ name: 'Forward-To', value: args.dominantToken },
				{ name: 'Forward-Action', value: 'Transfer' },)
		}

		const forwardedTags = [
			{ name: 'X-Order-Action', value: 'Create-Order' },
			{ name: 'X-Base-Token', value: args.baseToken }, // Primary token in the pair
			{ name: 'X-Quote-Token', value: args.quoteToken }, // Secondary token in the pair
			{ name: 'X-Base-Token-Denomination', value: args.baseTokenDenomination },
			{ name: 'X-Quote-Token-Denomination', value: args.quoteTokenDenomination },
			{ name: 'X-Dominant-Token', value: args.dominantToken }, // Token being sent this order (determines side: base=Ask, quote=Bid)
			{ name: 'X-Swap-Token', value: args.swapToken }, // Token being received this order
			{ name: 'X-Group-ID', value: MESSAGE_GROUP_ID },
		];

		/* Added for legacy profile support */
		const data = { Target: args.dominantToken, Action: 'Transfer', Input: {} };

		// Optional: Price for limit orders (if not provided, creates market order)
		if (args.unitPrice) forwardedTags.push({ name: 'X-Price', value: args.unitPrice.toString() });

		// Optional: Denomination of the dominant token (token being sent)
		if (args.denomination) forwardedTags.push({ name: 'X-Transfer-Denomination', value: args.denomination.toString() });

		tags.push(...forwardedTags);

		globalLog('Processing order...');
		callback({ processing: true, success: false, message: 'Processing your order...' });

		let transferId;
		if (args.creatorId) {
			transferId = await permaweb.sendMessage({
				processId: args.creatorId,
				action: args.action,
				tags: tags,
				data: data
			});
		}
		else {
			transferId = await permaweb.sendMessage({
				processId: args.dominantToken,
				action: 'Transfer',
				tags: tags
			})
		}

		globalLog(`Transfer ID: ${transferId}`);

		callback({ processing: false, success: true, message: 'Order Initiated' });

		return transferId;
	} catch (e: any) {
		throw new Error(e.message ?? 'Error creating order in UCM');
	}
}

export async function cancelOrder(
	deps: DependenciesType,
	args: OrderCancelType,
	callback: (args: { processing: boolean, success: boolean, message: string }) => void
): Promise<string> {
	const validationError = getOrderCancelErrorMessage(args);
	if (validationError) throw new Error(validationError);

	const permaweb = Permaweb.init(deps);

	try {
		const MESSAGE_GROUP_ID = Date.now().toString();

		const tags = [
			{ name: 'Action', value: 'Run-Action' },
			{ name: 'ForwardTo', value: args.orderbookId },
			{ name: 'ForwardAction', value: 'Cancel-Order' },
			{ name: 'Forward-To', value: args.orderbookId },
			{ name: 'Forward-Action', value: 'Cancel-Order' },
		];

		const data = {
			Target: args.orderbookId,
			Action: 'Cancel-Order',
			Input: {
				Pair: [args.dominantToken, args.swapToken],
				OrderTxId: args.orderId,
				['X-Group-ID']: MESSAGE_GROUP_ID
			}
		};

		globalLog('Cancelling order...')
		callback({ processing: true, success: false, message: 'Cancelling your order...' });

		const cancelOrderId = await permaweb.sendMessage({
			processId: args.creatorId,
			action: 'Run-Action',
			tags: tags,
			data: data
		});

		return cancelOrderId;
	} catch (e: any) {
		throw new Error(e.message ?? 'Error cancelling order in UCM');
	}
}

async function getMatchingMessages(
	processes: string[],
	groupId: string,
	successMatch: string[],
	errorMatch: string[],
	deps: DependenciesType,
	maxAttempts: number = MAX_RESULT_RETRIES,
	delayMs: number = 1000,
): Promise<string[]> {
	let currentMatchActions: string[] = [];
	let attempts = 0;

	function isMatch(currentMatchActions: string[], successMatch: string[], errorMatch: string[]): boolean {
		const currentSet = new Set(currentMatchActions);
		const successSet = new Set(successMatch);
		const errorSet = new Set(errorMatch);

		return (
			successSet.size === currentSet.size && [...successSet].every((action) => currentSet.has(action)) ||
			errorSet.size === currentSet.size && [...errorSet].every((action) => currentSet.has(action))
		);
	}

	let messagesByGroupId = null;

	do {
		attempts++;
		messagesByGroupId = await getMessagesByGroupId(processes, groupId, deps);

		currentMatchActions = messagesByGroupId
			.map((message: any) => getTagValue(message.Tags, 'Action'))
			.filter((action): action is string => action !== null);

		globalLog(`Attempt ${attempts} for results...`);

		if (!isMatch(currentMatchActions, successMatch, errorMatch)) {
			await new Promise((resolve) => setTimeout(resolve, delayMs));
		}
	} while (!isMatch(currentMatchActions, successMatch, errorMatch) && attempts < maxAttempts);

	if (!isMatch(currentMatchActions, successMatch, errorMatch)) {
		throw new Error('Failed to match actions within retry limit.');
	}

	for (const match of currentMatchActions) {
		globalLog('Match found:', match);
	}

	return messagesByGroupId;
}

async function getMessagesByGroupId(processes: string[], groupId: string, deps: DependenciesType): Promise<any[]> {
	const resultsByGroupId = [];
	for (const process of processes) {
		const messageResults = await deps.ao.results({
			process: process,
			sort: 'DESC',
			limit: 100,
		});

		if (messageResults?.edges?.length) {
			for (const result of messageResults.edges) {
				if (result.node?.Messages?.length) {
					for (const message of result.node.Messages) {
						const messageGroupId = getTagValue(message.Tags, 'X-Group-ID');
						if (messageGroupId === groupId) resultsByGroupId.push(message);
					}
				}
			}
		}
	}

	return resultsByGroupId;
}

function getOrderCreationErrorMessage(args: OrderCreateType): string | null {
	if (typeof args !== 'object' || args === null) return 'The provided arguments are invalid or empty.';
	if (typeof args.orderbookId !== 'string' || args.orderbookId.trim() === '') return 'Orderbook ID is required';
	if ((typeof args.creatorId !== 'string' || args.creatorId.trim() === '') && (typeof args.walletAddress !== 'string' || args.walletAddress.trim() === '')) return 'Profile ID or Wallet Address is required';
	if (typeof args.dominantToken !== 'string' || args.dominantToken.trim() === '') return 'Dominant token is required';
	if (typeof args.swapToken !== 'string' || args.swapToken.trim() === '') return 'Swap token is required';
	if (typeof args.quantity !== 'string' || args.quantity.trim() === '') return 'Quantity is required';
	if ('unitPrice' in args && typeof args.unitPrice !== 'string') return 'Unit price is invalid';
	if ('denomination' in args && typeof args.denomination !== 'string') return 'Denomination is invalid';
	return null;
}

function getOrderCancelErrorMessage(args: OrderCancelType): string | null {
	if (typeof args !== 'object' || args === null) return 'The provided arguments are invalid or empty.';
	if (typeof args.orderbookId !== 'string' || args.orderbookId.trim() === '') return 'Orderbook ID is required';
	if (typeof args.orderId !== 'string' || args.orderId.trim() === '') return 'Order ID is required';
	if (typeof args.creatorId !== 'string' || args.creatorId.trim() === '') return 'Profile ID is required';
	if (typeof args.dominantToken !== 'string' || args.dominantToken.trim() === '') return 'Dominant token is required';
	if (typeof args.swapToken !== 'string' || args.swapToken.trim() === '') return 'Swap token is required';
	return null;
}