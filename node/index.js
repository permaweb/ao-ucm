import { readFileSync } from 'node:fs';

import Arweave from 'arweave';
import { createDataItemSigner, dryrun, message, result } from '@permaweb/aoconnect';

const UCM_PROCESS = 'RDNSwCBS1TLoj9E9gman_Bhe0UsA5v-A7VmfDoWmZ-A';
const ASSET_PROCESS = 'u2kzJz1hoslvFadOSVUhFsc1IKy8B0KMxdGNTiu6KBo';
const TOKEN_PROCESS = 'Z6qlHim8aRabSbYFuxA03Tfi2T-83gPqdwot7TiwP0Y';

const ORDER_QUANTITY = '5';
const ORDER_PRICE = '100';

const ORDER_PAIR_SELL = [ASSET_PROCESS, TOKEN_PROCESS];
const ORDER_PAIR_BUY = [TOKEN_PROCESS, ASSET_PROCESS];

const SELLER_WALLET = JSON.parse(
	readFileSync('./wallets/seller-wallet.json').toString(),
);

const BUYER_WALLET = JSON.parse(
	readFileSync('./wallets/buyer-wallet.json').toString(),
);

// const UCM_OWNER_WALLET = JSON.parse(
// 	readFileSync('./wallets/owner-wallet.json').toString(),
// );

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

		let responseStatus = null;
		let responseMessage = null;

		if (Messages && Messages.length && Messages[Messages.length - 1].Tags) {
			responseStatus = getTagValue(Messages[Messages.length - 1].Tags, 'Status');
			responseMessage = getTagValue(Messages[Messages.length - 1].Tags, 'Message');
		}

		if (responseMessage && responseStatus) {
			console.log(`${responseStatus}: ${responseMessage}`)
		}

		console.log(`${args.action}: ${txId}`)

		return {
			txId: txId,
			responseStatus: responseStatus,
			responseMessage: responseMessage
		};
	}
	catch (e) {
		console.error(e);
	}
}

// args: { clientWallet, orderPair, orderQuantity, orderPrice? }
async function handleOrderCreate(args) {
	const dominantToken = args.orderPair[0];

	// try {
	// 	console.log('Transferring balance to client...');
	// 	const arweave = Arweave.init({});
	// 	const clientAddress = await arweave.wallets.jwkToAddress(args.clientWallet);
	// 	const transferResponse = await sendMessage({
	// 		processId: dominantToken, action: 'Transfer', wallet: UCM_OWNER_WALLET, data: {
	// 			Recipient: clientAddress,
	// 			Quantity: args.orderQuantity
	// 		}
	// 	});
	// 	console.log(transferResponse);
	// }
	// catch (e) {
	// 	console.error(e)
	// }

	try {
		console.log('Adding pair...');
		const addPairResponse = await sendMessage({ processId: UCM_PROCESS, action: 'Add-Pair', wallet: args.clientWallet, data: args.orderPair });
		console.log(addPairResponse);

		console.log('Allowing UCM to claim balance...');
		const allowResponse = await sendMessage({
			processId: dominantToken, action: 'Allow', wallet: args.clientWallet, data: {
				Recipient: UCM_PROCESS,
				Quantity: args.orderQuantity
			}
		});
		console.log(allowResponse);

		if (allowResponse && allowResponse.responseStatus && allowResponse.responseStatus === 'Success') {
			console.log('Claiming balance from UCM...');
			const claimResponse = await sendMessage({
				processId: UCM_PROCESS, action: 'Claim', wallet: args.clientWallet, data: {
					Pair: args.orderPair,
					AllowTxId: allowResponse.txId,
					Quantity: args.orderQuantity
				}
			});
			console.log(claimResponse);

			console.log('Checking claim status...');
			let claimStatusResponse = await sendMessage({
				processId: UCM_PROCESS, action: 'Check-Claim-Status', wallet: args.clientWallet, data: {
					Pair: args.orderPair,
					AllowTxId: allowResponse.txId
				}
			});
			console.log(claimStatusResponse);

			let currentClaimStatus = null;
			if (claimStatusResponse && claimStatusResponse.responseStatus) {
				currentClaimStatus = claimStatusResponse.responseStatus;
				while (currentClaimStatus === 'Pending') {
					console.log('Checking claim status...');
					await new Promise((r) => setTimeout(r, 1000));
					claimStatusResponse = await sendMessage({
						processId: UCM_PROCESS, action: 'Check-Claim-Status', wallet: args.clientWallet, data: {
							Pair: args.orderPair,
							AllowTxId: allowResponse.txId
						}
					});
					console.log(claimStatusResponse);
					currentClaimStatus = claimStatusResponse.responseStatus;
				}
				if (claimStatusResponse.responseStatus === 'Error') {
					console.error('Claim failed, cancelling allow...')
					const cancelAllowResponse = await sendMessage({
						processId: dominantToken, action: 'Cancel-Allow', wallet: args.clientWallet, data: {
							TxId: allowResponse.txId
						}
					});
					console.log(cancelAllowResponse);
				}
				else {
					if (claimStatusResponse.responseStatus === 'Success') {
						console.log('Creating order...');
						const orderData = {
							Pair: args.orderPair,
							AllowTxId: allowResponse.txId,
							Quantity: args.orderQuantity,
						}
						if (args.orderPrice) orderData.Price = args.orderPrice;

						const createOrderResponse = await sendMessage({
							processId: UCM_PROCESS, action: 'Create-Order', wallet: args.clientWallet, data: orderData
						});
						console.log(createOrderResponse);
					}
					else {
						console.error('Claim failed, cancelling allow...')
						const cancelAllowResponse = await sendMessage({
							processId: dominantToken, action: 'Cancel-Allow', wallet: args.clientWallet, data: {
								TxId: allowResponse.txId
							}
						});
						console.log(cancelAllowResponse);
					}
				}
			}
		}
		else {
			console.error('Allow not found')
		}
	}
	catch (e) {
		console.error(e)
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
	
	await new Promise((r) => setTimeout(r, 1000));

	// Buy order
	await handleOrderCreate({
		clientWallet: BUYER_WALLET,
		orderPair: ORDER_PAIR_BUY,
		orderQuantity: (parseInt(ORDER_QUANTITY) * parseInt(ORDER_PRICE)).toString(),
	});
})()