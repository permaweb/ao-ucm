import fs from 'fs';

import Arweave from 'arweave';
import { connect, createDataItemSigner, message } from '@permaweb/aoconnect';
import Permaweb from '@permaweb/libs';
import { createOrder, createOrderbook } from '@permaweb/ucm';

const NUM_LISTING_INSTANCES = 1;
const NUM_PURCHASE_INSTANCES = 0;
const ORDERS_PER_INSTANCE = 10000;

const SWAP_TOKEN = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10';
const CONNECT_MODE = 'mainnet';
const CONNECT_URL = 'http://relay.ao-hb.xyz';
const CU_URL = 'http://cu.s451-comm3-main.xyz';
const MU_URL = 'http://mu.s451-comm3-main.xyz';

const arweave = Arweave.init();

function logUpdate(message) {
	console.log('\x1b[33m%s\x1b[0m', `\n${message}`);
}

function logError(message) {
	console.error('\x1b[31m%s\x1b[0m', `Error (${message})`);
}

async function createInstance(args, overallTotals) {
	function createCountingCallback(spawnCount, messageCount, originalCallback) {
		return function (callbackData) {
			overallTotals.spawns += spawnCount;
			overallTotals.messages += messageCount;
			if (originalCallback) {
				originalCallback(callbackData);
			}
		};
	}

	try {
		logUpdate('Creating profile...');
		const profileId = await args.permaweb.createProfile({
			userName: 'My username',
			displayName: 'My display name',
			description: 'My description'
		}, createCountingCallback(1, 2, (status) => {
			console.log(`Callback: ${status}`);
		}));
		console.log(`Profile ID: ${profileId}`);

		let assetId = args.assetId;
		let orderbookId = args.orderbookId;
		if (args.type === 'listing' && (!assetId || !orderbookId)) {
			logUpdate('Creating atomic asset...');
			assetId = await args.permaweb.createAtomicAsset({
				name: 'Example Name',
				description: 'Example Description',
				topics: ['Topic 1', 'Topic 2', 'Topic 3'],
				creator: profileId,
				data: 'Atomic Asset Data',
				contentType: 'text/plain',
				assetType: 'Example Atomic Asset Type',
				supply: 1000000,
				metadata: {
					status: 'Initial Status'
				}
			}, createCountingCallback(1, 1, (status) => {
				console.log(`Atomic asset callback: ${status}`);
			}));
			console.log(`Asset ID: ${assetId}`);

			orderbookId = await createOrderbook(
				args.dependencies,
				{ assetId: assetId },
				createCountingCallback(2, 6, (cbArgs) => {
					console.log(cbArgs.message);
				})
			);
			console.log(`Orderbook ID: ${orderbookId}`);
		}

		const orderData = {
			orderbookId: orderbookId,
			creatorId: profileId,
			quantity: '1'
		};

		if (args.type === 'listing') {
			orderData.dominantToken = assetId;
			orderData.swapToken = SWAP_TOKEN;
			orderData.unitPrice = '1';
		} else {
			orderData.dominantToken = SWAP_TOKEN;
			orderData.swapToken = assetId;

			if (args.controller) {
				await message({
					process: SWAP_TOKEN,
					signer: createDataItemSigner(args.controller),
					tags: [
						{ name: 'Action', value: 'Transfer' },
						{ name: 'Recipient', value: profileId },
						{ name: 'Quantity', value: '1' },
					]
				});
			}
		}

		logUpdate(`Creating ${args.type} order on asset...`);
		const orderId = await createOrder(
			args.dependencies,
			orderData,
			createCountingCallback(0, 5, (cbArgs) => {
				console.log(cbArgs.message);
			})
		);
		console.log(`${args.type.charAt(0).toUpperCase() + args.type.slice(1).toLowerCase()} ID: ${orderId}`);

		const responseData = {
			profileId: profileId,
			assetId: assetId,
			orderbookId: orderbookId,
			orderId: orderId,
		};

		return responseData;
	} catch (e) {
		throw new Error(e.message ?? 'Error creating order');
	}
}

(async function () {
	const overallTotals = { spawns: 0, messages: 0 };

	const controller = JSON.parse(fs.readFileSync(process.env.PATH_TO_WALLET));
	console.log(`Controller: ${await arweave.wallets.jwkToAddress(controller)}`);

	function createCountingCallback(spawnCount, messageCount, originalCallback) {
		return function (callbackData) {
			overallTotals.spawns += spawnCount;
			overallTotals.messages += messageCount;
			if (originalCallback) {
				originalCallback(callbackData);
			}
		};
	}

	const listings = [];

	for (let i = 0; i < NUM_LISTING_INSTANCES; i++) {
		// logUpdate('Generating seller wallet...');
		// const sellerWallet = await arweave.wallets.generate();
		// const sellerWalletAddress = await arweave.wallets.jwkToAddress(sellerWallet);
		// console.log(`Seller wallet: ${sellerWalletAddress}`);

		const ao = connect({
			MODE: CONNECT_MODE,
			AO_URL: CONNECT_URL,
			wallet: controller // TODO: sellerWallet
		});
		const dependenciesSeller = { ao, arweave, signer: createDataItemSigner(controller) };
		const permawebSeller = Permaweb.init(dependenciesSeller);

		logUpdate(`Creating listing instance ${i + 1}...`);
		try {
			const listing = await createInstance({
				type: 'listing',
				permaweb: permawebSeller,
				dependencies: dependenciesSeller
			}, overallTotals);
			
			listings.push(listing);
			console.log(`Listing instance ${i + 1} created. Asset ID: ${listing.assetId}, Orderbook ID: ${listing.orderbookId}`);

			for (let j = 0; j < ORDERS_PER_INSTANCE; j++) {
				const orderData = {
					orderbookId: listing.orderbookId,
					creatorId: listing.profileId,
					quantity: '1',
					unitPrice: '1',
					dominantToken: assetId,
					swapToken: SWAP_TOKEN
				};
	
				logUpdate(`Creating listing order ${j + 1} for instance ${i + 1}...`);
				const orderId = await createOrder(
					dependenciesSeller,
					orderData,
					createCountingCallback(0, 5, (cbArgs) => {
						console.log(`Additional order callback for instance ${i + 1}: ${cbArgs.message}`);
					})
				);
				console.log(`Additional order ${j + 1} for instance ${i + 1} ID: ${orderId}`);
			}
		}
		catch (e) {
			logError(e.message ?? 'Error creating listing instance');
			process.exit(1);
		}
	}

	for (let i = 0; i < NUM_PURCHASE_INSTANCES; i++) {
		// logUpdate('Generating buyer wallet...');
		// const buyerWallet = await arweave.wallets.generate();
		// const buyerWalletAddress = await arweave.wallets.jwkToAddress(buyerWallet);
		// console.log(`Buyer wallet: ${buyerWalletAddress}`);

		const ao = connect({
			MODE: CONNECT_MODE,
			AO_URL: CONNECT_URL,
			wallet: controller // TODO: buyerWallet
		});
		const dependenciesBuyer = { ao, arweave, signer: createDataItemSigner(controller) };
		const permawebBuyer = Permaweb.init(dependenciesBuyer);

		const randomIndex = Math.floor(Math.random() * listings.length);
		const randomListing = listings[randomIndex];

		logUpdate(`Creating purchase ${i + 1} using listing ${randomIndex + 1}...`);
		const purchase = await createInstance({
			type: 'purchase',
			permaweb: permawebBuyer,
			dependencies: dependenciesBuyer,
			controller: controller,
			assetId: randomListing.assetId,
			orderbookId: randomListing.orderbookId
		}, overallTotals);
		console.log(`Purchase instance ${i + 1} created. Order ID: ${purchase.orderId}`);

		await message({
			process: SWAP_TOKEN,
			signer: createDataItemSigner(args.controller),
			tags: [
				{ name: 'Action', value: 'Transfer' },
				{ name: 'Recipient', value: purchase.profileId },
				{ name: 'Quantity', value: ORDERS_PER_INSTANCE.toString() },
			]
		});

		for (let j = 0; j < ORDERS_PER_INSTANCE; j++) {
			const orderData = {
				orderbookId: purchase.orderbookId,
				creatorId: purchase.profileId,
				quantity: '1',
				dominantToken: SWAP_TOKEN,
				swapToken: purchase.assetId
			};

			logUpdate(`Creating purchase order ${j + 1} for instance ${i + 1}...`);
			const orderId = await createOrder(
				dependenciesBuyer,
				orderData,
				createCountingCallback(0, 5, (cbArgs) => {
					console.log(`Additional order callback for instance ${i + 1}: ${cbArgs.message}`);
				})
			);
			console.log(`Additional order ${j + 1} for instance ${i + 1} ID: ${orderId}`);
		}
	}

	console.log(`Overall totals: Spawns: ${overallTotals.spawns}, Messages: ${overallTotals.messages}`);
})();