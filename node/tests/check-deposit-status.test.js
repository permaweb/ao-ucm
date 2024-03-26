import { test } from 'uvu';
import * as assert from 'uvu/assert';

import { BUYER_WALLET, ORDER_PAIR_SELL, readState, sendMessage, UCM_PROCESS } from '../index.js';

test('Check-Deposit-Status - Input-Error', async () => {
	console.log('Checking deposit status...');
	let depositCheckResponse = await sendMessage({
		processId: UCM_PROCESS, action: 'Check-Deposit-Status', wallet: BUYER_WALLET, data: {
			Pair: [],
			DepositTxId: null,
			Quantity: null
		}
	});
	assert.equal(depositCheckResponse['Input-Error'].status, 'Error');
	assert.equal(depositCheckResponse['Input-Error'].message, 'Invalid arguments, required { Pair: [TokenId, TokenId], DepositTxId, Quantity }');
});

test('Check-Deposit-Status - Validation-Error', async () => {
	console.log('Checking deposit status...');
	let depositCheckResponse = await sendMessage({
		processId: UCM_PROCESS, action: 'Check-Deposit-Status', wallet: BUYER_WALLET, data: {
			Pair: ORDER_PAIR_SELL,
			DepositTxId: 'Invalid deposit',
			Quantity: '100'
		}
	});
	assert.equal(depositCheckResponse['Validation-Error'].status, 'Error');
	assert.equal(depositCheckResponse['Validation-Error'].message, 'DepositTxId must be a valid address');
});

test('Check-Deposit-Status - Deposit-Status-Evaluated', async () => {
	console.log('Checking deposit status...');
	let depositCheckResponse = await sendMessage({
		processId: UCM_PROCESS, action: 'Check-Deposit-Status', wallet: BUYER_WALLET, data: {
			Pair: ORDER_PAIR_SELL,
			DepositTxId: 'K1J4PFhuFL_6a8D1X9nyXuNcJMfpnAcFK8BQ7sp76lw',
			Quantity: '100'
		}
	});
	assert.equal(depositCheckResponse['Deposit-Status-Evaluated'].status, 'Error');
	assert.equal(depositCheckResponse['Deposit-Status-Evaluated'].message, 'Deposit not found');
});

test.run();