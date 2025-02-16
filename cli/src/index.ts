import fs from 'fs';
import path from 'path';
import minimist from 'minimist';

import { CLI_ARGS } from './helpers/config';
import { ArgumentsInterface, CommandInterface, OptionInterface } from './helpers/types';
import { checkProcessEnv, log } from './helpers/utils';

(async function () {
	const argv = minimist(process.argv.slice(2));
	const command = argv._[0];
	const commandValues = argv._.slice(1);

	const fileFilter = checkProcessEnv(process.argv[0]);

	const commandFiles = fs.readdirSync(path.join(__dirname, 'commands')).filter((file) => file.endsWith(fileFilter));
	const commands: Map<string, CommandInterface> = new Map();
	for (const file of commandFiles) {
		const filePath = path.join(__dirname, 'commands', file);
		const { default: command } = require(filePath);
		if (command) {
			commands.set(command.name, command);
		}
	}

	const optionFiles = fs.readdirSync(path.join(__dirname, 'options')).filter((file) => file.endsWith(fileFilter));
	const options: Map<string, OptionInterface> = new Map();

	for (const file of optionFiles) {
		const filePath = path.join(__dirname, 'options', file);

		const { default: option } = require(filePath);
		options.set(option.name, option);
	}

	const args: ArgumentsInterface = {
		argv: argv,
		commandValues: commandValues,
		options: options,
		commands: commands,
	};

	if (commands.has(command)) {
		await commands.get(command).execute(args);
	} else {
		if (command) log(`Command not found: ${command}`, 1);
		commands.get(CLI_ARGS.commands.help).execute(args);
	}
})();

// const fs = require('fs');
// import { createObjectCsvWriter } from 'csv-writer';

// import { createDataItemSigner, dryrun, message, results } from '@permaweb/aoconnect';
// import { readFileSync } from 'fs';

// export const AO = {
// 	ucm: 'hqdL4AZaFZ0huQHbAsYxdTwG6vpibK7ALWKNzmWaD4Q',
// 	ucmActivity: '7_psKu3QHwzc2PFCJk2lEwyitLJbz6Vj7hOcltOulj4',
// 	pixl: 'DM3FoZUq_yebASPhgd8pEIRIzDW6muXEhxz5-JwbZwo',
// 	profileRegistry: 'SNy4m-DrqxWl01YqGM4sxI8qCni-58re8uuJLvZPypY',
// };

// export function getTagValue(list: { [key: string]: any }[], name: string): string | null {
// 	for (let i = 0; i < list.length; i++) {
// 		if (list[i]) {
// 			if (list[i]!.name === name) {
// 				return list[i]!.value as string;
// 			}
// 		}
// 	}
// 	return null;
// }

// export const PAGINATORS = {
// 	default: 100
// };

// export const CURSORS = {
// 	p1: 'P1',
// 	end: 'END',
// };

// export const GATEWAYS = {
// 	arweave: 'arweave.net',
// 	goldsky: 'arweave-search.goldsky.com',
// };

// export type TagType = { name: string; value: string };

// export type TagFilterType = { name: string; values: string[]; match?: string };

// export type BaseGQLArgsType = {
// 	ids: string[] | null;
// 	tagFilters: TagFilterType[] | null;
// 	owners: string[] | null;
// 	cursor: string | null;
// 	recipients: string[] | null;
// 	paginator?: number;
// 	minBlock?: number;
// 	maxBlock?: number;
// };

// export type GQLArgsType = { gateway: string } & BaseGQLArgsType;

// export type QueryBodyGQLArgsType = BaseGQLArgsType & { gateway?: string; queryKey?: string };

// export type BatchGQLArgsType = {
// 	gateway: string;
// 	entries: { [queryKey: string]: BaseGQLArgsType };
// };

// export type GQLNodeResponseType = {
// 	cursor: string | null;
// 	node: {
// 		id: string;
// 		tags: TagType[];
// 		data: {
// 			size: string;
// 			type: string;
// 		};
// 		block?: {
// 			height: number;
// 			timestamp: number;
// 		};
// 		owner?: {
// 			address: string;
// 		};
// 		recipient?: string;
// 		address?: string;
// 		timestamp?: number;
// 	};
// };

// export type GQLResponseType = {
// 	count: number;
// 	nextCursor: string | null;
// 	previousCursor: string | null;
// };

// export type DefaultGQLResponseType = {
// 	data: GQLNodeResponseType[];
// } & GQLResponseType;

// export type BatchAGQLResponseType = { [queryKey: string]: DefaultGQLResponseType };

// export type AOProfileType = {
// 	id: string;
// 	walletAddress: string;
// 	displayName: string | null;
// 	username: string | null;
// 	bio: string | null;
// 	avatar: string | null;
// 	banner: string | null;
// 	version: string | null;
// };

// export type ProfileHeaderType = AOProfileType;

// export async function getGQLData(args: GQLArgsType): Promise<DefaultGQLResponseType> {
// 	const paginator = args.paginator ? args.paginator : PAGINATORS.default;

// 	let data: GQLNodeResponseType[] = [];
// 	let count: number = 0;
// 	let nextCursor: string | null = null;

// 	if (args.ids && !args.ids.length) {
// 		return { data: data, count: count, nextCursor: nextCursor, previousCursor: null };
// 	}

// 	try {
// 		let queryBody: string = getQueryBody(args);
// 		const response = await getResponse({ gateway: args.gateway, query: getQuery(queryBody) });

// 		if (response.data.transactions.edges.length) {
// 			data = [...response.data.transactions.edges];
// 			count = response.data.transactions.count ?? 0;

// 			const lastResults: boolean = data.length < paginator || !response.data.transactions.pageInfo.hasNextPage;

// 			if (lastResults) nextCursor = CURSORS.end;
// 			else nextCursor = data[data.length - 1].cursor;

// 			return {
// 				data: data,
// 				count: count,
// 				nextCursor: nextCursor,
// 				previousCursor: null,
// 			};
// 		} else {
// 			return { data: data, count: count, nextCursor: nextCursor, previousCursor: null };
// 		}
// 	} catch (e: any) {
// 		console.error(e);
// 		return { data: data, count: count, nextCursor: nextCursor, previousCursor: null };
// 	}
// }

// export async function getBatchGQLData(args: BatchGQLArgsType): Promise<BatchAGQLResponseType> {
// 	let responseObject: BatchAGQLResponseType = {};
// 	let queryBody: string = '';

// 	for (const [queryKey, baseArgs] of Object.entries(args.entries)) {
// 		responseObject[queryKey] = { data: [], count: 0, nextCursor: null, previousCursor: null };
// 		queryBody += getQueryBody({ ...baseArgs, gateway: args.gateway, queryKey: queryKey });
// 	}

// 	try {
// 		const response = await getResponse({ gateway: args.gateway, query: getQuery(queryBody) });

// 		if (response && response.data) {
// 			for (const queryKey of Object.keys(response.data)) {
// 				const paginator = args.entries[queryKey].paginator ? args.entries[queryKey].paginator : PAGINATORS.default;

// 				let data: GQLNodeResponseType[] = [];
// 				let count: number = 0;
// 				let nextCursor: string | null = null;

// 				if (response.data[queryKey].edges.length) {
// 					data = [...response.data[queryKey].edges];
// 					count = response.data[queryKey].count ?? 0;

// 					const lastResults: boolean = data.length < paginator || !response.data[queryKey].pageInfo.hasNextPage;

// 					if (lastResults) nextCursor = CURSORS.end;
// 					else nextCursor = data[data.length - 1].cursor;

// 					responseObject[queryKey] = {
// 						data: [...response.data[queryKey].edges],
// 						count: count,
// 						nextCursor: nextCursor,
// 						previousCursor: null,
// 					};
// 				}
// 			}
// 		}
// 		return responseObject;
// 	} catch (e: any) {
// 		console.error(e);
// 		return responseObject;
// 	}
// }

// function getQuery(body: string): string {
// 	const query = { query: `query { ${body} }` };
// 	return JSON.stringify(query);
// }

// function getQueryBody(args: QueryBodyGQLArgsType): string {
// 	const paginator = args.paginator ? args.paginator : PAGINATORS.default;
// 	const ids = args.ids ? JSON.stringify(args.ids) : null;
// 	let blockFilter: { min?: number; max?: number } | null = null;
// 	if (args.minBlock !== undefined && args.minBlock !== null) {
// 		blockFilter = {};
// 		blockFilter.min = args.minBlock;
// 	}
// 	const blockFilterStr = blockFilter ? JSON.stringify(blockFilter).replace(/"([^"]+)":/g, '$1:') : null;
// 	const tagFilters = args.tagFilters
// 		? JSON.stringify(args.tagFilters)
// 			.replace(/"(name)":/g, '$1:')
// 			.replace(/"(values)":/g, '$1:')
// 			.replace(/"FUZZY_OR"/g, 'FUZZY_OR')
// 		: null;
// 	const owners = args.owners ? JSON.stringify(args.owners) : null;
// 	const cursor = args.cursor && args.cursor !== CURSORS.end ? `"${args.cursor}"` : null;

// 	let fetchCount: string = `first: ${paginator}`;
// 	let txCount: string = '';
// 	let nodeFields: string = `recipient data { size type } owner { address } block { height timestamp }`;
// 	let order: string = '';
// 	let recipients: string = '';

// 	switch (args.gateway) {
// 		case GATEWAYS.arweave:
// 			break;
// 		case GATEWAYS.goldsky:
// 			txCount = args.cursor && args.cursor !== CURSORS.end ? '' : 'count';
// 			recipients = `recipients: ${JSON.stringify(args.recipients)}`;
// 			break;
// 	}

// 	let body = `
// 		transactions(
// 				ids: ${ids},
// 				tags: ${tagFilters},
// 				${fetchCount},
// 				owners: ${owners},
// 				block: ${blockFilterStr},
// 				after: ${cursor},
// 				${order}
// 				${recipients}
// 			){
// 			${txCount}
// 			pageInfo {
// 				hasNextPage
// 			}
// 			edges {
// 				cursor
// 				node {
// 					id
// 					tags {
// 						name 
// 						value 
// 					}
// 					${nodeFields}
// 				}
// 			}
// 		}`;

// 	if (args.queryKey) body = `${args.queryKey}: ${body}`;

// 	return body;
// }

// async function getResponse(args: { gateway: string; query: string }): Promise<any> {
// 	try {
// 		const response = await fetch(`https://${args.gateway}/graphql`, {
// 			method: 'POST',
// 			headers: { 'Content-Type': 'application/json' },
// 			body: args.query,
// 		});
// 		return await response.json();
// 	} catch (e: any) {
// 		throw e;
// 	}
// }

// export async function messageResults(args: {
// 	processId: string;
// 	wallet: any;
// 	action: string;
// 	tags: TagType[] | null;
// 	data: any;
// 	responses?: string[];
// 	handler?: string;
// }): Promise<any> {
// 	try {
// 		const tags = [{ name: 'Action', value: args.action }];
// 		if (args.tags) tags.push(...args.tags);

// 		await message({
// 			process: args.processId,
// 			signer: createDataItemSigner(args.wallet),
// 			tags: tags,
// 			data: JSON.stringify(args.data),
// 		});

// 		await new Promise((resolve) => setTimeout(resolve, 500));

// 		const messageResults = await results({
// 			process: args.processId,
// 			sort: 'DESC',
// 			limit: 100,
// 		});

// 		if (messageResults && messageResults.edges && messageResults.edges.length) {
// 			const response: any = {};

// 			for (const result of messageResults.edges) {
// 				if (result.node && result.node.Messages && result.node.Messages.length) {
// 					const resultSet = [args.action];
// 					if (args.responses) resultSet.push(...args.responses);

// 					for (const message of result.node.Messages) {
// 						const action = getTagValue(message.Tags, 'Action');

// 						if (action) {
// 							let responseData = null;
// 							const messageData = message.Data;

// 							if (messageData) {
// 								try {
// 									responseData = JSON.parse(messageData);
// 								} catch {
// 									responseData = messageData;
// 								}
// 							}

// 							const responseStatus = getTagValue(message.Tags, 'Status');
// 							const responseMessage = getTagValue(message.Tags, 'Message');

// 							if (action === 'Action-Response') {
// 								const responseHandler = getTagValue(message.Tags, 'Handler');
// 								if (args.handler && args.handler === responseHandler) {
// 									response[action] = {
// 										status: responseStatus,
// 										message: responseMessage,
// 										data: responseData,
// 									};
// 								}
// 							} else {
// 								if (resultSet.includes(action)) {
// 									response[action] = {
// 										status: responseStatus,
// 										message: responseMessage,
// 										data: responseData,
// 									};
// 								}
// 							}

// 							if (Object.keys(response).length === resultSet.length) break;
// 						}
// 					}
// 				}
// 			}

// 			return response;
// 		}

// 		return null;
// 	} catch (e) {
// 		console.error(e);
// 	}
// }

// export async function readHandler(args: {
// 	processId: string;
// 	action: string;
// 	tags?: TagType[];
// 	data?: any;
// }): Promise<any> {
// 	const tags = [{ name: 'Action', value: args.action }];
// 	if (args.tags) tags.push(...args.tags);
// 	let data = JSON.stringify(args.data || {});

// 	const response = await dryrun({
// 		process: args.processId,
// 		tags: tags,
// 		data: data,
// 	});

// 	if (response.Messages && response.Messages.length) {
// 		if (response.Messages[0].Data) {
// 			return JSON.parse(response.Messages[0].Data);
// 		} else {
// 			if (response.Messages[0].Tags) {
// 				return response.Messages[0].Tags.reduce((acc: any, item: any) => {
// 					acc[item.name] = item.value;
// 					return acc;
// 				}, {});
// 			}
// 		}
// 	}
// }

// export function formatDate(dateArg: string | number | null, dateType: any, fullTime?: boolean) {
// 	if (!dateArg) {
// 		return null;
// 	}

// 	let date: Date | null = null;

// 	switch (dateType) {
// 		case 'iso':
// 			date = new Date(dateArg);
// 			break;
// 		case 'epoch':
// 			date = new Date(Number(dateArg));
// 			break;
// 		default:
// 			date = new Date(dateArg);
// 			break;
// 	}

// 	return fullTime
// 		? `${date.toLocaleString('default', { month: 'long' })} ${date.getDate()}, ${date.getUTCFullYear()} ${date.getHours() % 12 || 12
// 		}:${date.getMinutes().toString().padStart(2, '0')}:${date.getSeconds().toString().padStart(2, '0')} ${date.getHours() >= 12 ? 'PM' : 'AM'
// 		}`
// 		: `${date.toLocaleString('default', { month: 'long' })} ${date.getDate()}, ${date.getUTCFullYear()}`;
// }

// export async function getProfileById(args: { profileId: string }): Promise<any | null> {
// 	const emptyProfile = {
// 		id: args.profileId,
// 		walletAddress: null,
// 		displayName: null,
// 		username: null,
// 		bio: null,
// 		avatar: null,
// 		banner: null,
// 		version: null,
// 	};

// 	try {
// 		const fetchedProfile = await readHandler({
// 			processId: args.profileId,
// 			action: 'Info',
// 			data: null,
// 		});

// 		if (fetchedProfile) {
// 			return {
// 				id: args.profileId,
// 				walletAddress: fetchedProfile.Owner || null,
// 				displayName: fetchedProfile.Profile.DisplayName || null,
// 				username: fetchedProfile.Profile.UserName || null,
// 				bio: fetchedProfile.Profile.Description || null,
// 				avatar: fetchedProfile.Profile.ProfileImage || null,
// 				banner: fetchedProfile.Profile.CoverImage || null,
// 				version: fetchedProfile.Profile.Version || null,
// 				assets: fetchedProfile.Assets?.map((asset: { Id: string; Quantity: string }) => asset.Id) ?? [],
// 			};
// 		} else return emptyProfile;
// 	} catch (e: any) {
// 		throw new Error(e);
// 	}
// }

// export async function getProfileByWalletAddress(args: { address: string }): Promise<ProfileHeaderType | null> {
// 	const emptyProfile = {
// 		id: null,
// 		walletAddress: args.address,
// 		displayName: null,
// 		username: null,
// 		bio: null,
// 		avatar: null,
// 		banner: null,
// 		version: null,
// 	};

// 	try {
// 		const profileLookup = await readHandler({
// 			processId: AO.profileRegistry,
// 			action: 'Get-Profiles-By-Delegate',
// 			data: { Address: args.address },
// 		});

// 		let activeProfileId: string;
// 		if (profileLookup && profileLookup.length > 0 && profileLookup[0].ProfileId) {
// 			activeProfileId = profileLookup[0].ProfileId;
// 		}

// 		if (activeProfileId) {
// 			const fetchedProfile = await readHandler({
// 				processId: activeProfileId,
// 				action: 'Info',
// 				data: null,
// 			});

// 			if (fetchedProfile) {
// 				return {
// 					id: activeProfileId,
// 					walletAddress: fetchedProfile.Owner || null,
// 					displayName: fetchedProfile.Profile.DisplayName || null,
// 					username: fetchedProfile.Profile.UserName || null,
// 					bio: fetchedProfile.Profile.Description || null,
// 					avatar: fetchedProfile.Profile.ProfileImage || null,
// 					banner: fetchedProfile.Profile.CoverImage || null,
// 					version: fetchedProfile.Profile.Version || null,
// 				};
// 			} else return emptyProfile;
// 		} else return emptyProfile;
// 	} catch (e: any) {
// 		throw new Error(e);
// 	}
// }

// async function mapActivity(orders: any, event: 'Listing' | 'Purchase' | 'Sale' | 'Unlisted') {
// 	let updatedActivity = [];

// 	if (orders && orders.length > 0) {
// 		const mappedActivity = orders.map((order: any) => {
// 			let orderEvent = event;
// 			return {
// 				orderId: order.OrderId,
// 				dominantToken: order.DominantToken,
// 				swapToken: order.SwapToken,
// 				price: order.Price.toString(),
// 				quantity: order.Quantity.toString(),
// 				sender: order.Sender || '-',
// 				receiver: order.Receiver || '-',
// 				timestamp: formatDate(order.Timestamp, 'iso', true),
// 				event: orderEvent,
// 			};
// 		});

// 		updatedActivity = mappedActivity;
// 	}

// 	return updatedActivity;
// }

// let logData = '';

// const appendToLog = (message: string) => {
// 	logData += message + '\n';
// 	console.log(message);
// };

// async function fetchData(fetchParams: GQLArgsType, processElementCallback: (element: GQLNodeResponseType) => void) {
// 	let fetchResult = await getGQLData(fetchParams);

// 	if (fetchResult && fetchResult.data.length) {
// 		let aggregatedData = fetchResult.data;
// 		appendToLog(`Count: ${fetchResult.count}`);

// 		while (fetchResult.nextCursor && fetchResult.nextCursor !== CURSORS.end) {
// 			appendToLog('Fetching next page...');
// 			await new Promise((resolve) => setTimeout(resolve, 1000));

// 			fetchResult = await getGQLData({
// 				...fetchParams,
// 				cursor: fetchResult.nextCursor,
// 			});

// 			if (fetchResult && fetchResult.data.length) {
// 				aggregatedData = aggregatedData.concat(fetchResult.data);
// 			}
// 		}

// 		const actionCounts = {};

// 		aggregatedData.forEach((element) => {
// 			const action = getTagValue(element.node.tags, 'Action');
// 			actionCounts[action] = (actionCounts[action] || 0) + 1;
// 			processElementCallback(element);
// 		});

// 		return actionCounts;
// 	}
// 	else {
// 		appendToLog('No data found');
// 	}

// 	return null;
// }

// export async function getTransferData(target: string) {
// 	appendToLog(`Target: ${target}`);

// 	// console.log('Running outgoing fetch...');
// 	// await fetchData({
// 	// 	gateway: GATEWAYS.goldsky,
// 	// 	ids: null,
// 	// 	tagFilters: [{ name: 'From-Process', values: [target] }],
// 	// 	owners: null,
// 	// 	cursor: null,
// 	// 	recipients: null
// 	// }, (element: GQLNodeResponseType) => {
// 	// 	if (getTagValue(element.node.tags, 'Action') === 'Transfer') {
// 	// 		console.log(`Transfer sent by ${getTagValue(element.node.tags, 'From-Process')}`);
// 	// 		console.log(`Target: ${getTagValue(element.node.tags, 'Target')}`);
// 	// 		console.log(`Recipient: ${getTagValue(element.node.tags, 'Recipient')}`);
// 	// 		console.log(`Quantity: ${Number(getTagValue(element.node.tags, 'Quantity'))}\n`);
// 	// 	}
// 	// });

// 	// console.log('Running incoming fetch...');
// 	// await fetchData({
// 	// 	gateway: GATEWAYS.goldsky,
// 	// 	ids: null,
// 	// 	tagFilters: null,
// 	// 	owners: null,
// 	// 	cursor: null,
// 	// 	recipients: [target]
// 	// }, (element: GQLNodeResponseType) => {
// 	// 	if (getTagValue(element.node.tags, 'Action') === 'Transfer') {
// 	// 		console.log(`Transfer sent by ${element.node.owner.address} to ${element.node.recipient}`);
// 	// 		console.log(`Target: ${getTagValue(element.node.tags, 'Target')}`);
// 	// 		console.log(`Recipient: ${getTagValue(element.node.tags, 'Recipient')}`);
// 	// 		console.log(`Quantity: ${Number(getTagValue(element.node.tags, 'Quantity'))}\n`);
// 	// 	}
// 	// });

// 	appendToLog('Running incoming transfers...');
// 	const senderQuantities = {};

// 	await fetchData({
// 		gateway: GATEWAYS.goldsky,
// 		ids: null,
// 		tagFilters: [
// 			{ name: 'Action', values: ['Credit-Notice'] },
// 			// { name: 'From-Process', values: ['xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'] }
// 			{ name: 'From-Process', values: ['DM3FoZUq_yebASPhgd8pEIRIzDW6muXEhxz5-JwbZwo'] }
// 		],
// 		owners: null,
// 		cursor: null,
// 		recipients: [target],
// 		minBlock: 1480164
// 	}, (element: GQLNodeResponseType) => {
// 		const sender = getTagValue(element.node.tags, 'Sender');
// 		const quantity = Number(getTagValue(element.node.tags, 'Quantity'));
// 		const timestamp = element.node.block.timestamp;
// 		const date = new Date(timestamp * 1000);
// 		const formattedDate = date.toLocaleString();

// 		const logMessage = `${formattedDate}: ${sender} -> ${target}: ${quantity} (${Number(quantity) / Math.pow(10, 6)}) PIXL`;
// 		appendToLog(logMessage);

// 		if (sender) {
// 			senderQuantities[sender] = (senderQuantities[sender] || 0) + quantity;
// 		}
// 	});

// 	for (const [sender, totalQuantity] of Object.entries(senderQuantities)) {
// 		const logMessage = `Total transfers from ${sender}: ${totalQuantity} (${Number(totalQuantity) / Math.pow(10, 6)}) PIXL`;
// 		appendToLog(logMessage);
// 	}

// 	const filePath = `${process.env.HOME}/Downloads/${target}.txt`;

// 	fs.writeFileSync(filePath, logData);
// 	console.log(`\nLogs written successfully to ${filePath}`);
// }

// export async function getUCMActivity() {
// 	const AssetIds = null;
// 	const Address = 'HiWY083YQJZx8ybNxOOHm61Na7R-WtPkZCtEQNoF1P8';
// 	const StartDate = null;
// 	const EndDate = null;

// 	console.log('Getting UCM activity...');
// 	try {
// 		let data: any = {};

// 		if (AssetIds) data.AssetIds = AssetIds;
// 		if (Address) data.Address = Address;
// 		if (StartDate) data.StartDate = StartDate;
// 		if (EndDate) data.EndDate = EndDate;

// 		const response = await readHandler({
// 			processId: AO.ucmActivity,
// 			action: 'Get-Activity',
// 			data: data,
// 		});

// 		if (response) {
// 			let updatedActivity = [];
// 			if (response.ListedOrders) updatedActivity.push(...await mapActivity(response.ListedOrders, 'Listing'));
// 			if (response.ExecutedOrders)
// 				updatedActivity.push(...await mapActivity(response.ExecutedOrders, 'Sale'));
// 			if (response.CancelledOrders)
// 				updatedActivity.push(...await mapActivity(response.CancelledOrders, 'Unlisted'));

// 			let fileName = `UCM-Activity`;
// 			if (StartDate) fileName += `-${formatDate(Number(StartDate), 'iso').replace(/, /g, '-').replaceAll(' ', '-')}`;
// 			if (EndDate) fileName += `-${formatDate(Number(EndDate), 'iso').replace(/, /g, '-').replaceAll(' ', '-')}`;
// 			if (Address) fileName += `-${Address}`;
// 			fileName += '.csv';

// 			const filePath = `${process.env.HOME}/Downloads/${fileName}`;

// 			const csvWriter = createObjectCsvWriter({
// 				path: filePath,
// 				header: [
// 					{ id: 'orderId', title: 'Order ID' },
// 					{ id: 'dominantToken', title: 'Dominant Token' },
// 					{ id: 'swapToken', title: 'Swap Token' },
// 					{ id: 'price', title: 'Price' },
// 					{ id: 'quantity', title: 'Quantity' },
// 					{ id: 'sender', title: 'Sender' },
// 					{ id: 'receiver', title: 'Receiver' },
// 					{ id: 'timestamp', title: 'Timestamp' },
// 					{ id: 'event', title: 'Event' },
// 				],
// 			});

// 			await csvWriter.writeRecords(updatedActivity);
// 			console.log(`Logs written successfully to ${filePath} `);
// 		}
// 		else {
// 			console.log('No data found');
// 		}
// 	}
// 	catch (e) {
// 		console.error(e);
// 	}
// }

// export async function getProfilesByWalletAddresses(args: { addresses: string[] }) {
// 	console.log('Running profile lookup...');
// 	const profileLookup = await readHandler({
// 		processId: AO.profileRegistry,
// 		action: 'Read-Profiles',
// 		data: { Addresses: args.addresses },
// 	});

// 	const timestamp = new Date().toISOString().replace(/:/g, '-').replace(/\..+/, '');
// 	let fileName = `Profile-Lookup-${timestamp}`;
// 	fileName += '.csv';

// 	const filePath = `${process.env.HOME}/Downloads/${fileName}`;

// 	if (profileLookup && profileLookup.length > 0) {
// 		const csvWriter = createObjectCsvWriter({
// 			path: filePath,
// 			header: [
// 				{ id: 'ProfileId', title: 'Profile ID' },
// 				{ id: 'CallerAddress', title: 'Wallet Address' }
// 			],
// 		});

// 		await csvWriter.writeRecords(profileLookup);
// 		console.log(`Logs written successfully to ${filePath} `);
// 	}
// 	else {
// 		console.log('No data found');
// 	}
// }

// export async function handleCollectionReturn(collectionId: string) {
// 	try {
// 		const assetsToTransfer = [];
// 		const listedAssets = [];

// 		const ucmResponse = await readHandler({
// 			processId: AO.ucm,
// 			action: 'Info'
// 		});

// 		const collectionResponse = await readHandler({
// 			processId: collectionId,
// 			action: 'Info'
// 		});

// 		if (ucmResponse?.Orderbook && collectionResponse?.Assets) {
// 			for (const entry of ucmResponse.Orderbook) {
// 				if (collectionResponse.Assets.includes(entry.Pair[0]) && entry.Orders?.length) {
// 					listedAssets.push(entry.Pair[0]);
// 				}
// 			}
// 		}

// 		const filteredAssets = collectionResponse.Assets.filter((assetId: string) => !listedAssets.includes(assetId));

// 		for (const assetId of filteredAssets) {
// 			try {
// 				const balancesResponse = await readHandler({
// 					processId: assetId,
// 					action: 'Balances'
// 				});

// 				if (balancesResponse && balancesResponse[AO.ucm]) {
// 					assetsToTransfer.push({ Id: assetId, Quantity: balancesResponse[AO.ucm] });
// 					console.log(`Asset (${assetId}) owned by UCM, Balance: ${balancesResponse[AO.ucm]}`);
// 				}
// 			}
// 			catch (e: any) {
// 				console.error(`Error on asset (${assetId})`);
// 				console.error(e.message ?? e);
// 			}
// 		}

// 		if (assetsToTransfer.length > 0) {
// 			console.log(`Running transfer on ${assetsToTransfer.length} assets...`)
// 			await messageResults({
// 				processId: AO.ucm,
// 				action: 'Return-Transfer',
// 				wallet: JSON.parse(readFileSync(process.env.UCM_OWNER).toString()),
// 				tags: [{ name: 'Recipient', value: 'ypjwVnuXu5h4Hlz45M46yABxv3f1qjziCQmcz5PoDaA' }],
// 				data: { AssetsToTransfer: assetsToTransfer }
// 			});
// 		}
// 	}
// 	catch (e: any) {
// 		console.error(e);
// 	}
// }

// async function getStreaks() {
// 	try {
// 		const streaks = await readHandler({
// 			processId: AO.pixl,
// 			action: 'Get-Streaks',
// 		});

// 		const mappedStreaks = Object.entries(streaks.Streaks).map(([id, details]) => ({
// 			ID: id,
// 			Days: (details as any).days,
// 			LastHeight: (details as any).lastHeight,
// 		}));

// 		const timestamp = new Date().toISOString().replace(/:/g, '-').replace(/\..+/, '');
// 		let fileName = `Streaks-${timestamp}`;
// 		fileName += '.csv';

// 		const filePath = `${process.env.HOME}/Downloads/${fileName}`;

// 		const csvWriter = createObjectCsvWriter({
// 			path: filePath,
// 			header: [
// 				{ id: 'ID', title: 'ID' },
// 				{ id: 'Days', title: 'Days' },
// 				{ id: 'LastHeight', title: 'LastHeight' },
// 			],
// 		});

// 		await csvWriter.writeRecords(mappedStreaks);
// 		console.log(`Logs written successfully to ${filePath}`);
// 	} catch (e: any) {
// 		console.error(e);
// 	}
// }

// function printUsage() {
// 	console.log("\nUsage:");
// 	console.log("  node script.js <command> [parameters]\n");
// 	console.log("Commands:");
// 	console.log("  handleCollectionReturn <collectionId>   Process a collection return with the given ID.");
// 	console.log("  getStreaks                              Retrieve streaks data.");
// 	console.log("  getTransferData <walletAddress>         Get transfer data for the given wallet address.\n");
// }

// const args = process.argv.slice(2);
// const command = args[0];

// (async function () {
// 	if (!command) {
// 		console.error("No command provided.");
// 		printUsage();
// 		process.exit(1);
// 	}

// 	switch (command) {
// 		case 'streaks': {
// 			await getStreaks();
// 			break;
// 		}
// 		case 'transfer-data': {
// 			const walletAddress = args[1];
// 			if (!walletAddress) {
// 				console.error("Error: 'getTransferData' requires a wallet address.");
// 				printUsage();
// 				process.exit(1);
// 			}
// 			await getTransferData(walletAddress);
// 			break;
// 		}
// 		default: {
// 			console.error(`Unknown command: ${command}`);
// 			printUsage();
// 			process.exit(1);
// 		}
// 	}
// })();