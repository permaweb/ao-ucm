import { createDataItemSigner, message, results } from '@permaweb/aoconnect';

import { OrderCancelType, OrderCreateType } from 'helpers/types';
import { getTagValue, getTagValueForAction, globalLog } from 'helpers/utils';

const MAX_RESULT_RETRIES = 100;

export async function createOrder(
	args: OrderCreateType,
	wallet: any,
	callback: (args: { processing: boolean, success: boolean, message: string }) => void
): Promise<string> {
	const validationError = getOrderCreationErrorMessage(args);
	if (validationError) throw new Error(validationError);

	try {
		const MESSAGE_GROUP_ID = Date.now().toString();

		const tags = [
			{ name: 'Action', value: 'Transfer' },
			{ name: 'Target', value: args.dominantToken },
			{ name: 'Recipient', value: args.orderbookId },
			{ name: 'Quantity', value: args.quantity },
		];

		const forwardedTags = [
			{ name: 'X-Order-Action', value: 'Create-Order' },
			{ name: 'X-Dominant-Token', value: args.dominantToken },
			{ name: 'X-Swap-Token', value: args.swapToken },
			{ name: 'X-Group-ID', value: MESSAGE_GROUP_ID },
		];

		if (args.unitPrice) forwardedTags.push({ name: 'X-Price', value: args.unitPrice.toString() });
		if (args.denomination) forwardedTags.push({ name: 'X-Transfer-Denomination', value: args.denomination.toString() });

		tags.push(...forwardedTags);

		globalLog('Processing order...')
		callback({ processing: true, success: false, message: 'Processing your order...' });

		const transferId = await message({
			process: args.profileId,
			signer: createDataItemSigner(wallet),
			tags: tags,
		});

		const baseMatchActions = ['Transfer'];
		const successMatch = [...baseMatchActions, 'Order-Success'];
		const errorMatch = [...baseMatchActions, 'Order-Error'];

		try {
			const messagesByGroupId = await getMatchingMessages(
				[args.profileId, args.orderbookId],
				MESSAGE_GROUP_ID,
				successMatch,
				errorMatch
			);

			const currentMatchActions = messagesByGroupId
				.map((message: any) => getTagValue(message.Tags, 'Action'))
				.filter((action): action is string => action !== null);

			const isSuccess = successMatch.every(action => currentMatchActions.includes(action));
			const isError = errorMatch.every(action => currentMatchActions.includes(action));

			if (isSuccess) {
				const successMessage = getTagValueForAction(messagesByGroupId, 'Message', 'Order-Success', 'Order created 2!');
				callback({ processing: false, success: true, message: successMessage });
			} else if (isError) {
				const errorMessage = getTagValueForAction(messagesByGroupId, 'Message', 'Order-Error', 'Order failed 2');
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
	args: OrderCancelType,
	wallet: any,
	callback: (args: { processing: boolean, success: boolean, message: string }) => void
): Promise<string> {
	const validationError = getOrderCancelErrorMessage(args);
	if (validationError) throw new Error(validationError);

	try {
		const MESSAGE_GROUP_ID = Date.now().toString();

		const tags = [
			{ name: 'Action', value: 'Run-Action' },
		];

		const data = JSON.stringify({
			Target: args.orderbookId,
			Action: 'Cancel-Order',
			Input: JSON.stringify({
				Pair: [args.dominantToken, args.swapToken],
				OrderTxId: args.orderId,
				['X-Group-ID']: MESSAGE_GROUP_ID
			}),
		});

		globalLog('Cancelling order...')
		callback({ processing: true, success: false, message: 'Cancelling your order...' });

		const cancelOrderId = await message({
			process: args.profileId,
			signer: createDataItemSigner(wallet),
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
	maxAttempts: number = MAX_RESULT_RETRIES,
	delayMs: number = 1000
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
		messagesByGroupId = await getMessagesByGroupId(processes, groupId);

		currentMatchActions = messagesByGroupId
			.map((message: any) => getTagValue(message.Tags, 'Action'))
			.filter((action): action is string => action !== null);

		globalLog(`Attempt ${attempts}:`, currentMatchActions);

		if (!isMatch(currentMatchActions, successMatch, errorMatch)) {
			await new Promise((resolve) => setTimeout(resolve, delayMs));
		}
	} while (!isMatch(currentMatchActions, successMatch, errorMatch) && attempts < maxAttempts);

	if (!isMatch(currentMatchActions, successMatch, errorMatch)) {
		throw new Error('Failed to match actions within retry limit.');
	}

	globalLog('Match found:', currentMatchActions);

	return messagesByGroupId;
}

async function getMessagesByGroupId(processes: string[], groupId: string): Promise<any[]> {
	const resultsByGroupId = [];
	for (const process of processes) {
		const messageResults = await results({
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
	if (typeof args.profileId !== 'string' || args.profileId.trim() === '') return 'Profile ID is required';
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
	if (typeof args.profileId !== 'string' || args.profileId.trim() === '') return 'Profile ID is required';
	if (typeof args.dominantToken !== 'string' || args.dominantToken.trim() === '') return 'Dominant token is required';
	if (typeof args.swapToken !== 'string' || args.swapToken.trim() === '') return 'Swap token is required';

	return null;
}