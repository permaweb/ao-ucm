import { readFileSync } from 'node:fs';

import Arweave from 'arweave';
import { createDataItemSigner, dryrun, message, result } from '@permaweb/aoconnect';

const ASSET_PROCESS = 'ZDqYPs4B7j7lyfU79_xN6AZmnf49HpOz4QrTOl0YEvE';
const UCM_PROCESS = 'RDNSwCBS1TLoj9E9gman_Bhe0UsA5v-A7VmfDoWmZ-A';
const TOKEN_PROCESS = 'j5njRTLL6myHN2dPJKOAxQBPLj3ZuDzO6N5rR_yl8dM';

const ORDER_QUANTITY = '5';
const ORDER_PRICE = '100';

const ORDER_PAIR_SELL = [ASSET_PROCESS, TOKEN_PROCESS];
const ORDER_PAIR_BUY = [TOKEN_PROCESS, ASSET_PROCESS];

const CLIENT_WALLET = JSON.parse(
	readFileSync('./wallets/client-wallet.json').toString(),
);

const OWNER_WALLET = JSON.parse(
	readFileSync('./wallets/owner-wallet.json').toString(),
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

// async function readState(processId) {
// 	const messageResult = await dryrun({
// 		process: processId,
// 		tags: [{ name: 'Action', value: 'Read' }],
// 	});

// 	if (messageResult.Messages && messageResult.Messages.length && messageResult.Messages[0].Data) {
// 		return JSON.parse(messageResult.Messages[0].Data);
// 	}
// }

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

		console.log(`${args.action}: ${txId}\n`)

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

async function handleSellOrder() {
	try {
		console.log('Transferring balance to client...');
		const arweave = Arweave.init({});
		const clientAddress = await arweave.wallets.jwkToAddress(CLIENT_WALLET);
		const transferResponse = await sendMessage({
			processId: ASSET_PROCESS, action: 'Transfer', wallet: OWNER_WALLET, data: {
				Recipient: clientAddress,
				Quantity: ORDER_QUANTITY
			}
		});
	}
	catch (e) {
		console.error(e)
	}

	try {
		console.log('Adding pair...');
		const addPairResponse = await sendMessage({ processId: UCM_PROCESS, action: 'Add-Pair', wallet: CLIENT_WALLET, data: ORDER_PAIR_SELL });

		// console.log('Allowing UCM to claim balance...');
		// const allowResponse = await sendMessage({
		// 	processId: ASSET_PROCESS, action: 'Allow', wallet: CLIENT_WALLET, data: {
		// 		Recipient: UCM_PROCESS,
		// 		Quantity: ORDER_QUANTITY
		// 	}
		// });

		console.log('Creating sell order in UCM...');
		const createOrderResponse = await sendMessage({
			processId: UCM_PROCESS, action: 'Create-Order', wallet: CLIENT_WALLET, data: {
				Pair: ORDER_PAIR_SELL,
				AllowTxId: allowResponse.txId,
				Quantity: ORDER_QUANTITY,
				Price: ORDER_PRICE
			}
		});

		// console.log('Checking order status in UCM...');
		// let checkOrderStatusResponse = await sendMessage({
		// 	processId: UCM_PROCESS, action: 'Check-Order-Status', wallet: CLIENT_WALLET, data: {
		// 		Pair: ORDER_PAIR_SELL,
		// 		AllowTxId: allowResponse.txId
		// 	}
		// });

		// let currentStatus = null;
		// if (checkOrderStatusResponse && checkOrderStatusResponse.responseStatus && checkOrderStatusResponse.responseStatus === 'Pending') {
		// 	currentStatus = checkOrderStatusResponse.responseStatus;
		// 	while (currentStatus === 'Pending') {
		// 		console.log('Checking order status in UCM...');
		// 		checkOrderStatusResponse = await sendMessage({
		// 			processId: UCM_PROCESS, action: 'Check-Order-Status', wallet: CLIENT_WALLET, data: {
		// 				Pair: ORDER_PAIR_SELL,
		// 				AllowTxId: allowResponse.txId
		// 			}
		// 		});
		// 		currentStatus = checkOrderStatusResponse.responseStatus;
		// 	}
		// }
	}
	catch (e) {
		console.error(e)
	}
}

async function handleBuyOrder() {
	// try {
	// 	console.log('Transferring balance to client...');
	// 	const arweave = Arweave.init({});
	// 	const clientAddress = await arweave.wallets.jwkToAddress(CLIENT_WALLET);
	// 	const transferResponse = await sendMessage({
	// 		processId: TOKEN_PROCESS, action: 'Transfer', wallet: OWNER_WALLET, data: {
	// 			Recipient: clientAddress,
	// 			Quantity: ORDER_PRICE
	// 		}
	// 	});
	// }
	// catch (e) {
	// 	console.error(e)
	// }

	try {
		// console.log('Adding pair...');
		// const addPairResponse = await sendMessage({ processId: UCM_PROCESS, action: 'Add-Pair', wallet: CLIENT_WALLET, data: ORDER_PAIR_SELL });

		// console.log('Allowing UCM to claim balance...');
		// const allowResponse = await sendMessage({
		// 	processId: TOKEN_PROCESS, action: 'Allow', wallet: CLIENT_WALLET, data: {
		// 		Recipient: UCM_PROCESS,
		// 		Quantity: ORDER_PRICE
		// 	}
		// });

		console.log('Creating buy order in UCM...');
		const createOrderResponse = await sendMessage({
			processId: UCM_PROCESS, action: 'Create-Order', wallet: CLIENT_WALLET, data: {
				Pair: ORDER_PAIR_BUY,
				AllowTxId: allowResponse.txId,
				Quantity: (parseInt(ORDER_PRICE) * parseInt(ORDER_QUANTITY)).toString(),
			}
		});

		// console.log('Checking order status in UCM...');
		// let checkOrderStatusResponse = await sendMessage({
		// 	processId: UCM_PROCESS, action: 'Check-Order-Status', wallet: CLIENT_WALLET, data: {
		// 		Pair: ORDER_PAIR_BUY,
		// 		AllowTxId: allowResponse.txId
		// 	}
		// });

		// let currentStatus = null;
		// if (checkOrderStatusResponse && checkOrderStatusResponse.responseStatus && checkOrderStatusResponse.responseStatus === 'Pending') {
		// 	currentStatus = checkOrderStatusResponse.responseStatus;
		// 	while (currentStatus === 'Pending') {
		// 		console.log('Checking order status in UCM...');
		// 		checkOrderStatusResponse = await sendMessage({
		// 			processId: UCM_PROCESS, action: 'Check-Order-Status', wallet: CLIENT_WALLET, data: {
		// 				Pair: ORDER_PAIR_BUY,
		// 				AllowTxId: allowResponse.txId
		// 			}
		// 		});
		// 		currentStatus = checkOrderStatusResponse.responseStatus;
		// 	}
		// }
	}
	catch (e) {
		console.error(e)
	}
}

(async function () {
	await handleSellOrder();
	// await handleBuyOrder();
})()