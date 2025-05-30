import Permaweb from '@permaweb/libs';

import { DependenciesType, OrderCancelType, OrderCreateType } from 'helpers/types';
import { getTagValue, getTagValueForAction, globalLog } from 'helpers/utils';

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
			{ name: 'Target', value: args.dominantToken },
			{ name: 'ForwardTo', value: args.dominantToken },
			{ name: 'ForwardAction', value: 'Transfer' },
			{ name: 'Recipient', value: args.orderbookId },
			{ name: 'Quantity', value: args.quantity },
		];

		const forwardedTags = [
			{ name: 'X-Order-Action', value: 'Create-Order' },
			{ name: 'X-Dominant-Token', value: args.dominantToken },
			{ name: 'X-Swap-Token', value: args.swapToken },
			{ name: 'X-Group-ID', value: MESSAGE_GROUP_ID },
		];

		/* Added for legacy profile support */
		const data = { Target: args.dominantToken, Action: 'Transfer', Input: {} };

		if (args.unitPrice) forwardedTags.push({ name: 'X-Price', value: args.unitPrice.toString() });
		if (args.denomination) forwardedTags.push({ name: 'X-Transfer-Denomination', value: args.denomination.toString() });

		tags.push(...forwardedTags);

		globalLog('Processing order...');
		callback({ processing: true, success: false, message: 'Processing your order...' });
		
		const transferId = await permaweb.sendMessage({
			processId: args.creatorId,
			action: args.action,
			tags: tags,
			data: data
		});

		const successMatch = ['Order-Success'];
		const errorMatch = ['Order-Error'];

		try {
			const messagesByGroupId = await getMatchingMessages(
				[args.orderbookId],
				MESSAGE_GROUP_ID,
				successMatch,
				errorMatch,
				deps
			);

			const currentMatchActions = messagesByGroupId
				.map((message: any) => getTagValue(message.Tags, 'Action'))
				.filter((action): action is string => action !== null);

			const isSuccess = successMatch.every(action => currentMatchActions.includes(action));
			const isError = errorMatch.every(action => currentMatchActions.includes(action));

			if (isSuccess) {
				const successMessage = getTagValueForAction(messagesByGroupId, 'Message', 'Order-Success', 'Order created!');
				callback({ processing: false, success: true, message: successMessage });
			} else if (isError) {
				const errorMessage = getTagValueForAction(messagesByGroupId, 'Message', 'Order-Error', 'Order failed');
				callback({ processing: false, success: false, message: errorMessage });
			} else {
				throw new Error('Unexpected state: Order not fully processed.');
			}

			return getTagValueForAction(messagesByGroupId, 'OrderId', 'Order-Success', transferId);
		}
		catch (e: any) {
			throw new Error(e);
		}
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
		];

		const data = JSON.stringify({
			Target: args.orderbookId,
			Action: 'Cancel-Order',
			Input: {
				Pair: [args.dominantToken, args.swapToken],
				OrderTxId: args.orderId,
				['X-Group-ID']: MESSAGE_GROUP_ID
			}
		});

		globalLog('Cancelling order...')
		callback({ processing: true, success: false, message: 'Cancelling your order...' });

		const cancelOrderId = await permaweb.sendMessage({
			processId: args.creatorId,
			action: 'Run-Action',
			tags: tags,
			data: data,
			useRawData: true
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
	if (typeof args.creatorId !== 'string' || args.creatorId.trim() === '') return 'Profile ID is required';
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