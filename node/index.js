import { readFileSync } from 'node:fs';

import { createDataItemSigner, dryrun, message, result } from '@permaweb/aoconnect';

export const UCM_PROCESS = 'RDNSwCBS1TLoj9E9gman_Bhe0UsA5v-A7VmfDoWmZ-A';
export const ASSET_PROCESS = 'u2kzJz1hoslvFadOSVUhFsc1IKy8B0KMxdGNTiu6KBo';
export const TOKEN_PROCESS = 'Z6qlHim8aRabSbYFuxA03Tfi2T-83gPqdwot7TiwP0Y';

export const ORDER_QUANTITY = '1';
export const ORDER_PRICE = '100';

export const ORDER_PAIR_SELL = [ASSET_PROCESS, TOKEN_PROCESS];
export const ORDER_PAIR_BUY = [TOKEN_PROCESS, ASSET_PROCESS];

export const SELLER_WALLET = JSON.parse(
	readFileSync('./wallets/seller-wallet.json').toString(),
);

export const BUYER_WALLET = JSON.parse(
	readFileSync('./wallets/buyer-wallet.json').toString(),
);

export const TOKEN_OWNER_WALLET = JSON.parse(
	readFileSync('./wallets/token-owner.json').toString(),
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

export async function readState(processId) {
	const messageResult = await dryrun({
		process: processId,
		tags: [{ name: 'Action', value: 'Info' }],
	});

	if (messageResult.Messages && messageResult.Messages.length && messageResult.Messages[0].Data) {
		return JSON.parse(messageResult.Messages[0].Data);
	}
}

export async function sendMessage(args) {
	try {
		const txId = await message({
			process: args.processId,
			signer: createDataItemSigner(args.wallet),
			tags: [{ name: 'Action', value: args.action }],
			data: JSON.stringify(args.data)
		});

		const { Messages } = await result({ message: txId, process: args.processId });

		if (Messages && Messages.length) {
			const response = {};

			Messages.forEach((message) => {
				const action = getTagValue(message.Tags, 'Action') || args.action;

				console.log(message)

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
		console.log('Depositing balance to UCM...');
		const depositResponse = await sendMessage({
			processId: dominantToken, action: 'Transfer', wallet: args.clientWallet, data: {
				Recipient: UCM_PROCESS,
				Quantity: args.orderQuantity
			}
		});
		console.log(depositResponse);

		const validCreditNotice = depositResponse['Credit-Notice'] && depositResponse['Credit-Notice'].status === 'Success';

		if (validCreditNotice) {
			const depositTxId = depositResponse['Credit-Notice'].data.TransferTxId;

			console.log('Checking deposit status...');
			let depositCheckResponse = await sendMessage({
				processId: UCM_PROCESS, action: 'Check-Deposit-Status', wallet: args.clientWallet, data: {
					Pair: args.orderPair,
					DepositTxId: depositTxId,
					Quantity: args.orderQuantity
				}
			});
			console.log(depositCheckResponse)

			if (depositCheckResponse && depositCheckResponse['Deposit-Status-Evaluated']) {
				const MAX_DEPOSIT_CHECK_RETRIES = 10;

				let depositStatus = depositCheckResponse['Deposit-Status-Evaluated'].status;
				let retryCount = 0;

				while (depositStatus === 'Error' && retryCount < MAX_DEPOSIT_CHECK_RETRIES) {
					await new Promise((r) => setTimeout(r, 1000));
					depositCheckResponse = await sendMessage({
						processId: UCM_PROCESS, action: 'Check-Deposit-Status', wallet: args.clientWallet, data: {
							Pair: args.orderPair,
							DepositTxId: depositTxId,
							Quantity: args.orderQuantity
						}
					});
					console.log(depositCheckResponse);

					depositStatus = depositCheckResponse['Deposit-Status-Evaluated'].status;
					retryCount++;
				}

				if (depositStatus === 'Success') {
					console.log('Creating order...');
					const orderData = {
						Pair: args.orderPair,
						DepositTxId: depositResponse.id,
						Quantity: args.orderQuantity,
					}
					if (args.orderPrice) orderData.Price = args.orderPrice;

					const createOrderResponse = await sendMessage({
						processId: UCM_PROCESS, action: 'Create-Order', wallet: args.clientWallet, data: orderData
					});
					console.log(createOrderResponse);
				}
				else {
					console.error('Failed to resolve deposit status after 3 retries.');
				}
			}
			else {
				console.error('Failed to check deposit status')
			}
		}
		else {
			console.error('Invalid credit notice')
		}
	}
	catch (e) {
		console.error(e);
	}
}

// args: { clientWallet, orderPair, orderTxId }
async function handleOrderCancel(args) {
	try {
		console.log('Cancelling order...');
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

async function handleMint() {
	try {
		console.log('Minting tokens...');
		const mintResponse = await sendMessage({
			processId: TOKEN_PROCESS, action: 'Mint', wallet: TOKEN_OWNER_WALLET, data: {
				Quantity: '5',
			}
		});
		console.log(mintResponse);
	}
	catch (e) {
		console.error(e);
	}
}

(async function () {
	// await handleMint()
	
	// Sell order
	await handleOrderCreate({
		clientWallet: SELLER_WALLET,
		orderPair: ORDER_PAIR_SELL,
		orderQuantity: ORDER_QUANTITY,
		orderPrice: ORDER_PRICE
	});

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