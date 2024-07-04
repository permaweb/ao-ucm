import { readFileSync } from 'node:fs';

import { createDataItemSigner, message, results } from '@permaweb/aoconnect';

export const AO = {
	ucm: 'U3TjJAZWJjlWBB4KAXSHKzuky81jtyh0zqH8rUL4Wd0',
	defaultToken: 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
};

export function getTagValue(list: { [key: string]: any }[], name: string): string | null {
	for (let i = 0; i < list.length; i++) {
		if (list[i]) {
			if (list[i]!.name === name) {
				return list[i]!.value as string;
			}
		}
	}
	return null;
}

export type TagType = { name: string; value: string };

export async function messageResults(args: {
	processId: string;
	wallet: any;
	action: string;
	tags: TagType[] | null;
	data: any;
	responses?: string[];
	handler?: string;
}): Promise<any> {
	try {
		const tags = [{ name: 'Action', value: args.action }];
		if (args.tags) tags.push(...args.tags);

		await message({
			process: args.processId,
			signer: createDataItemSigner(args.wallet),
			tags: tags,
			data: JSON.stringify(args.data),
		});

		await new Promise((resolve) => setTimeout(resolve, 500));

		const messageResults = await results({
			process: args.processId,
			sort: 'DESC',
			limit: 100,
		});

		if (messageResults && messageResults.edges && messageResults.edges.length) {
			const response: any = {};

			for (const result of messageResults.edges) {
				if (result.node && result.node.Messages && result.node.Messages.length) {
					const resultSet = [args.action];
					if (args.responses) resultSet.push(...args.responses);

					for (const message of result.node.Messages) {
						const action = getTagValue(message.Tags, 'Action');

						if (action) {
							let responseData = null;
							const messageData = message.Data;

							if (messageData) {
								try {
									responseData = JSON.parse(messageData);
								} catch {
									responseData = messageData;
								}
							}

							const responseStatus = getTagValue(message.Tags, 'Status');
							const responseMessage = getTagValue(message.Tags, 'Message');

							if (action === 'Action-Response') {
								const responseHandler = getTagValue(message.Tags, 'Handler');
								if (args.handler && args.handler === responseHandler) {
									response[action] = {
										status: responseStatus,
										message: responseMessage,
										data: responseData,
									};
								}
							} else {
								if (resultSet.includes(action)) {
									response[action] = {
										status: responseStatus,
										message: responseMessage,
										data: responseData,
									};
								}
							}

							if (Object.keys(response).length === resultSet.length) break;
						}
					}
				}
			}

			return response;
		}

		return null;
	} catch (e) {
		console.error(e);
	}
}

(async function () {
	const ORDER_TYPE: any = 'sell';

	const PRIMARY_TOKEN = '0PPd-FXKcvcQIltWLy4rbGPxuirSzNpCHwr0J8keTdk'
	const PROFILE_PROCESS = 'SaXnsUgxJLkJRghWQOUs9-wB0npVviewTkUbh2Yk64M'
	const WALLET = JSON.parse(readFileSync('./wallets/wallet.json').toString());

	let pair: string[] | null = null;
	let forwardedTags: TagType[] | null = null;
	let recipient: string | null = null;

	switch (ORDER_TYPE) {
		case 'buy':
			pair = [AO.defaultToken, PRIMARY_TOKEN];
			recipient = AO.ucm;
			break;
		case 'sell':
			pair = [PRIMARY_TOKEN, AO.defaultToken];
			recipient = AO.ucm;
			break;
		case 'transfer':
			pair = [PRIMARY_TOKEN, AO.defaultToken];
			recipient = AO.ucm;
			break;
	}

	const dominantToken: string | null = pair[0];
	const swapToken: string | null = pair[1];
	const quantity: string | null = '1';
	const unitPrice: string | null = '10000000000';
	
	const primaryDenomination: number | null = null;
	const transferDenomination: number | null = null;

	if (ORDER_TYPE === 'buy' || ORDER_TYPE === 'sell') {
		forwardedTags = [
			{ name: 'X-Order-Action', value: 'Create-Order' },
			{ name: 'X-Quantity', value: quantity },
			{ name: 'X-Swap-Token', value: swapToken },
		];
		if (unitPrice && Number(unitPrice) > 0) {
			let calculatedUnitPrice: string | number = unitPrice;
			if (transferDenomination) calculatedUnitPrice = Number(unitPrice) * transferDenomination;
			calculatedUnitPrice = calculatedUnitPrice.toString();
			forwardedTags.push({ name: 'X-Price', value: calculatedUnitPrice });
		}
	}

	const transferTags = [
		{ name: 'Target', value: dominantToken },
		{ name: 'Recipient', value: recipient },
		{ name: 'Quantity', value: quantity },
	];

	if (forwardedTags) transferTags.push(...forwardedTags);

	for (let i = 0; i < 100; i++) {
		const response: any = await messageResults({
			processId: PROFILE_PROCESS,
			action: 'Transfer',
			wallet: WALLET,
			tags: transferTags,
			data: {
				Target: dominantToken,
				Recipient: recipient,
				Quantity: quantity,
			},
			responses: ['Transfer-Success', 'Transfer-Error'],
			handler: 'Create-Order',
		});
		
		console.log(response);
	}
})()