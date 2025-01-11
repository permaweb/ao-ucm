import { readFileSync, writeFileSync } from 'node:fs';

import { createDataItemSigner, message, result } from '@permaweb/aoconnect';

export const AO = {
	ucm: 'CDxd81DDaJvpzxoyhXn-dVnZhYIFQEKU8FeUHdktFgQ',
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

		return messageId;
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
		creatorId: string;
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
				{ name: 'Recipient', value: args.creator.creatorId },
			],
			data: null,
			responses: ['Transfer-Success', 'Transfer-Error'],
		});
		console.log(transferResponse);
	}

	console.log(`Creating ${orderType} order...`);

	const orderResponse: any = await messageResults({
		processId: args.creator.creatorId,
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

/* Test for attempting to fulfill orders multiple times, funds should be returned to the second buyer */
(async function () {
	const UNIT_PRICE = '100000000';
	const PRIMARY_TOKEN = '8GgPV3qrxFCM6qusrF3B00nfFN2mNXhXncptFuQdG6E';

	const seller = {
		creatorId: 'SaXnsUgxJLkJRghWQOUs9-wB0npVviewTkUbh2Yk64M',
		wallet: JSON.parse(readFileSync('./wallets/wallet-1-uf.json').toString()),
	}

	const buyers = {
		'9E_fOuT55QKfeXo6hL8Gr65ImtnNKa3s7qV7XUw1V00': {
			creatorId: '9E_fOuT55QKfeXo6hL8Gr65ImtnNKa3s7qV7XUw1V00',
			wallet: JSON.parse(readFileSync('./wallets/wallet-2-jnb.json').toString()),
		},
		'9lDJVGR9dohGhWmSW57D9pOpFEs_PPBBLb1b0OnlarE': {
			creatorId: '9lDJVGR9dohGhWmSW57D9pOpFEs_PPBBLb1b0OnlarE',
			wallet: JSON.parse(readFileSync('./wallets/wallet-3-c6.json').toString()),
		},
	};

	console.log('Handling initial transfers...')

	for (const buyer of Object.keys(buyers)) {
		const transferResponse = await messageResults({
			processId: AO.defaultToken,
			wallet: seller.wallet,
			action: 'Transfer',
			tags: [
				{ name: 'Recipient', value: buyer },
				{ name: 'Quantity', value: UNIT_PRICE },
			],
			data: null
		});

		console.log(`Transfer response: ${transferResponse}`);
	}

	const sellResponse = await createOrder({
		dominantToken: PRIMARY_TOKEN,
		swapToken: AO.defaultToken,
		quantity: '1',
		unitPrice: UNIT_PRICE,
		transferDenomination: 1,
		creator: seller
	});

	console.log(`Sell response: ${sellResponse}`);

	for (const buyer of Object.keys(buyers)) {
		const buyResponse = await createOrder({
			dominantToken: PRIMARY_TOKEN,
			swapToken: AO.defaultToken,
			quantity: UNIT_PRICE,
			transferDenomination: 1,
			creator: buyers[buyer]
		})

		console.log(`Buy response: ${buyResponse}`);
	}
})()