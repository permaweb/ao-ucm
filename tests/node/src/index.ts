import { readFileSync, writeFileSync } from 'node:fs';

import { createDataItemSigner, message, result, results } from '@permaweb/aoconnect';

export const AO = {
	ucm: 'qtDwylCwyhhsGPKIYAi2Ao342mdhvFUPqdbDOudzaiM',
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

		const messageId = await message({
			process: args.processId,
			signer: createDataItemSigner(args.wallet),
			tags: tags,
			data: JSON.stringify(args.data),
		});

		await new Promise((resolve) => setTimeout(resolve, 500));

		let messageResult = await result({
			process: args.processId,
			message: messageId
		});

		writeFileSync(`./logs/result-${args.processId}.txt`, JSON.stringify(messageResult, null, 2), { flag: 'w' });

		let messageResults = await results({
			process: args.processId,
			sort: 'DESC',
			limit: 100,
			from: ''
		});

		const cursor = messageResults.edges?.[messageResults.edges.length - 1]?.cursor ?? null

		console.log(`Message Id: ${messageId}`);

		if (messageResults && messageResults.edges && messageResults.edges.length) {
			const response: any = {};

			for (const result of messageResults.edges) {
				if (result.node && result.node.Messages && result.node.Messages.length) {
					const resultSet = [args.action];
					if (args.responses) resultSet.push(...args.responses);

					writeFileSync(`./logs/${args.processId}.txt`, JSON.stringify(result.node.Messages, null, 2), { flag: 'w' });

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
								// if (resultSet.includes(action)) {
								response[action] = {
									status: responseStatus,
									message: responseMessage,
									data: responseData,
								};
								// }
							}

							writeFileSync(`./logs/response-${args.processId}.txt`, JSON.stringify(response, null, 2), { flag: 'w' });

							// if (Object.keys(response).length === resultSet.length) break;
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

async function createOrder(args: {
	dominantToken: string;
	swapToken: string;
	unitPrice?: string;
	quantity: string;
	transferDenomination: number;
	creator: {
		profileId: string;
		wallet: any;
	}
}) {
	const orderType: any = args.unitPrice ? 'sell' : 'buy';

	let pair: string[] | null = null;
	let forwardedTags: TagType[] | null = null;
	let recipient: string | null = null;

	switch (orderType) {
		case 'buy':
			pair = [args.swapToken, args.dominantToken];
			recipient = AO.ucm;
			break;
		case 'sell':
			pair = [args.dominantToken, args.swapToken];
			recipient = AO.ucm;
			break;
		case 'transfer':
			pair = [args.dominantToken, args.swapToken];
			recipient = AO.ucm;
			break;
	}

	const dominantToken: string | null = pair[0];
	const swapToken: string | null = pair[1];

	if (orderType === 'buy' || orderType === 'sell') {
		forwardedTags = [
			{ name: 'X-Order-Action', value: 'Create-Order' },
			{ name: 'X-Swap-Token', value: swapToken },
		];
		if (args.unitPrice && Number(args.unitPrice) > 0) {
			let calculatedUnitPrice: string | number = args.unitPrice;
			if (args.transferDenomination) calculatedUnitPrice = Number(args.unitPrice) * args.transferDenomination;
			calculatedUnitPrice = calculatedUnitPrice.toString();
			forwardedTags.push({ name: 'X-Price', value: calculatedUnitPrice });
		}
	}

	const transferTags = [
		{ name: 'Target', value: dominantToken },
		{ name: 'Recipient', value: recipient },
		{ name: 'Quantity', value: args.quantity },
	];

	if (forwardedTags) transferTags.push(...forwardedTags);

	if (orderType === 'buy') {
		console.log(`Transferring ${args.quantity} ${dominantToken} to profile...`)
		const transferResponse: any = await messageResults({
			processId: dominantToken,
			action: 'Transfer',
			wallet: args.creator.wallet,
			tags: [
				{ name: 'Quantity', value: args.quantity },
				{ name: 'Recipient', value: args.creator.profileId },
			],
			data: null,
			responses: ['Transfer-Success', 'Transfer-Error'],
		});
		console.log(transferResponse);
	}

	console.log(`Creating ${orderType} order...`);

	const orderResponse: any = await messageResults({
		processId: args.creator.profileId,
		action: 'Transfer',
		wallet: args.creator.wallet,
		tags: transferTags,
		data: {
			Target: dominantToken,
			Recipient: recipient,
			Quantity: args.quantity,
		},
		responses: ['Transfer-Success', 'Transfer-Error', 'Order-Error'],
		handler: 'Create-Order',
	});

	return orderResponse;
}

(async function () {
	const primaryToken = '0PPd-FXKcvcQIltWLy4rbGPxuirSzNpCHwr0J8keTdk';

	const seller = {
		profileId: 'YMN2vh_oHx-jzPOXJHuGVYrXEpEbEAplNC8yNmFiBBQ',
		wallet: JSON.parse(readFileSync('./wallets/seller-wallet-c6.json').toString()),
	}

	const buyers = {
		'VkIkVlCws-dUzx_nISV9BxzM4fDrNfJ93kx6PMDdPzE': {
			profileId: 'VkIkVlCws-dUzx_nISV9BxzM4fDrNfJ93kx6PMDdPzE',
			wallet: JSON.parse(readFileSync('./wallets/buyer-wallet-1-uf.json').toString()),
		},
		'n1FZml-9sqWiSx0ErLuJMipNlUaroEBBvkCvNusQoCA': {
			profileId: 'n1FZml-9sqWiSx0ErLuJMipNlUaroEBBvkCvNusQoCA',
			wallet: JSON.parse(readFileSync('./wallets/buyer-wallet-2-jnb.json').toString()),
		},
	};

	const sellResponse = await createOrder({
		dominantToken: primaryToken,
		swapToken: AO.defaultToken,
		quantity: '2',
		unitPrice: '10000000000',
		transferDenomination: 1,
		creator: seller
	});

	console.log(sellResponse);

	createOrder({
		dominantToken: primaryToken,
		swapToken: AO.defaultToken,
		quantity: '10000000001',
		transferDenomination: 1,
		creator: buyers['n1FZml-9sqWiSx0ErLuJMipNlUaroEBBvkCvNusQoCA']
	}).then((response) => {
		console.log(response);
	});

	createOrder({
		dominantToken: primaryToken,
		swapToken: AO.defaultToken,
		quantity: '20000000001',
		transferDenomination: 1,
		creator: buyers['VkIkVlCws-dUzx_nISV9BxzM4fDrNfJ93kx6PMDdPzE']
	}).then((response) => {
		console.log(response);
	});

	let totalResults = [];
	console.log('Fetching results...');
	let resultsFetch = await results({
		process: 'VkIkVlCws-dUzx_nISV9BxzM4fDrNfJ93kx6PMDdPzE',
		sort: 'DESC',
		limit: 100,
		from: ''
	});

	totalResults.push(...resultsFetch.edges);

	let cursor = resultsFetch.edges?.[resultsFetch.edges.length - 1]?.cursor ?? null

	while (cursor) {
		console.log('Fetching results...');
		resultsFetch = await results({
			process: 'VkIkVlCws-dUzx_nISV9BxzM4fDrNfJ93kx6PMDdPzE',
			sort: 'DESC',
			limit: 100,
			from: cursor
		});

		totalResults.push(...resultsFetch.edges);
		cursor = resultsFetch.edges?.[resultsFetch.edges.length - 1]?.cursor ?? null;
	}

	writeFileSync(`./logs/out.json`, JSON.stringify(resultsFetch, null, 2), { flag: 'w' });
})()