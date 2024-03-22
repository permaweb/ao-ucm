import { readFileSync } from 'node:fs';

import Arweave from 'arweave';
import { createDataItemSigner, dryrun, message, result } from '@permaweb/aoconnect';

const UCM_PROCESS = 'RDNSwCBS1TLoj9E9gman_Bhe0UsA5v-A7VmfDoWmZ-A';
const ASSET_PROCESS = 'u2kzJz1hoslvFadOSVUhFsc1IKy8B0KMxdGNTiu6KBo';
const TOKEN_PROCESS = 'Z6qlHim8aRabSbYFuxA03Tfi2T-83gPqdwot7TiwP0Y';

const ORDER_QUANTITY = '1';
const ORDER_PRICE = '100';

const ORDER_PAIR_SELL = [ASSET_PROCESS, TOKEN_PROCESS];
const ORDER_PAIR_BUY = [TOKEN_PROCESS, ASSET_PROCESS];

const SELLER_WALLET = JSON.parse(
	readFileSync('./wallets/seller-wallet.json').toString(),
);

const BUYER_WALLET = JSON.parse(
	readFileSync('./wallets/buyer-wallet.json').toString(),
);

function getTagValue(list, name) {
	for (let i = 0; i < list.length; i++) {
		if (list[i]) {
			if (list[i].name === name) {
				return list[i].value;
			}
		}
	}
	return null;
}

async function readState(processId) {
	const messageResult = await dryrun({
		process: processId,
		tags: [{ name: 'Action', value: 'Read' }],
	});

	if (messageResult.Messages && messageResult.Messages.length && messageResult.Messages[0].Data) {
		return JSON.parse(messageResult.Messages[0].Data);
	}
}

async function sendMessage(args) {
	try {
		const txId = await message({
			process: args.processId,
			tags: [{ name: 'Action', value: args.action }],
			signer: createDataItemSigner(args.wallet),
			data: JSON.stringify(args.data)
		});

		const { Messages } = await result({ message: txId, process: args.processId });

		if (Messages && Messages.length) {
			const response = {};

			Messages.forEach((message) => {
				const action = getTagValue(message.Tags, 'Action') || args.action;

				let responseData = null;
				const messageData = message.Data;

				if (messageData) {
					try {
						responseData = JSON.parse(messageData);
					}
					catch {
						responseData = messageData;
					}
				}

				const responseStatus = getTagValue(message.Tags, 'Status');
				const responseMessage = getTagValue(message.Tags, 'Message');
				
				if (responseStatus && responseMessage) {
					console.log(`${responseStatus}: ${responseMessage}`);
				}

				response[action] = {
					id: txId,
					status: responseStatus,
					message: responseMessage,
					data: responseData
				}
			});

			console.log(`${args.action}: ${txId}`);

			return response;

		}
		else return null;
	}
	catch (e) {
		console.error(e);
	}
}

// args: { clientWallet, orderPair, orderQuantity, orderPrice? }
async function handleOrderCreate(args) {
	const dominantToken = args.orderPair[0];

	try {
		// console.log('Adding pair...');
		// const addPairResponse = await sendMessage({ processId: UCM_PROCESS, action: 'Add-Pair', wallet: args.clientWallet, data: args.orderPair });
		// console.log(addPairResponse);

		console.log('Depositing balance to UCM...');
		const depositResponse = await sendMessage({
			processId: dominantToken, action: 'Transfer', wallet: args.clientWallet, data: {
				Recipient: UCM_PROCESS,
				Quantity: args.orderQuantity
			}
		});
		console.log(depositResponse);

		// if (depositResponse && depositResponse.data && depositResponse.data.TransferTxId) {
		// 	console.log('Creating order...');
		// 	const orderData = {
		// 		Pair: args.orderPair,
		// 		DepositTxId: depositResponse.data.TransferTxId,
		// 		Quantity: args.orderQuantity,
		// 	}
		// 	if (args.orderPrice) orderData.Price = args.orderPrice;

		// 	const createOrderResponse = await sendMessage({
		// 		processId: UCM_PROCESS, action: 'Create-Order', wallet: args.clientWallet, data: orderData
		// 	});
		// 	console.log(createOrderResponse);
		// }
	}
	catch (e) {
		console.error(e);
	}
}

// args: { clientWallet, orderPair, orderTxId }
async function handleOrderCancel(args) {
	try {
		console.error('Cancelling order...')
		const cancelOrderResponse = await sendMessage({
			processId: UCM_PROCESS, action: 'Cancel-Order', wallet: args.clientWallet, data: {
				Pair: args.orderPair,
				OrderTxId: args.orderTxId
			}
		});
		console.log(cancelOrderResponse);
	}
	catch (e) {
		console.error(e);
	}
}

(async function () {
	// Sell order
	await handleOrderCreate({
		clientWallet: SELLER_WALLET,
		orderPair: ORDER_PAIR_SELL,
		orderQuantity: ORDER_QUANTITY,
		orderPrice: ORDER_PRICE
	});

	// await new Promise((r) => setTimeout(r, 1000));

	// Buy order
	// await handleOrderCreate({
	// 	clientWallet: BUYER_WALLET,
	// 	orderPair: ORDER_PAIR_BUY,
	// 	orderQuantity: ((parseInt(ORDER_QUANTITY) * parseInt(ORDER_PRICE))).toString(),
	// });

	// Cancel order
	// await handleOrderCancel({
	// 	clientWallet: SELLER_WALLET,
	// 	orderPair: ORDER_PAIR_SELL,
	// 	orderTxId: 'TGnNQjm4kqnSUwSNEdf4x_2ijrBHLhmccnAfs4GdEZ8'
	// });

	// Cancel allow
	// await handleAllowCancel({
	// 	clientWallet: SELLER_WALLET,
	// 	processId: ASSET_PROCESS,
	// 	txId: 'LmpOLlkTvzWeyQ1D5A2kAFxmqQlzt1wRVbVitLyuCLU'
	// })
})()