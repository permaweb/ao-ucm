import { createDataItemSigner, message, results } from '@permaweb/aoconnect';

import { OrderCreateType } from 'helpers/types';
import { getTagValue, getTagValueForAction } from 'helpers/utils';

const MAX_RESULT_RETRIES = 100;

// TODO: Args validation
export async function createOrder(
	args: OrderCreateType,
	wallet: any,
	callback: (args: { processing: boolean, success: boolean, message: string }) => void
): Promise<string> {
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

		console.log(`Attempt ${attempts}:`, currentMatchActions);

		if (!isMatch(currentMatchActions, successMatch, errorMatch)) {
			await new Promise((resolve) => setTimeout(resolve, delayMs));
		}
	} while (!isMatch(currentMatchActions, successMatch, errorMatch) && attempts < maxAttempts);

	if (!isMatch(currentMatchActions, successMatch, errorMatch)) {
		throw new Error('Failed to match actions within retry limit.');
	}

	console.log('Match found:', currentMatchActions);

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