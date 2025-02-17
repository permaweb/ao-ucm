import clc from 'cli-color';
import fs from 'fs';
import QuickChart from 'quickchart-js';

import { connect } from '@permaweb/aoconnect';
import Permaweb from '@permaweb/libs';

import { CLI_ARGS, DAILY_HEIGHT_INTERVAL, ENDPOINTS } from '../helpers/config';
import { ArgumentsInterface, CommandInterface } from '../helpers/types';
import { CliSpinner, formatCount, getTagValue, log } from '../helpers/utils';

interface DataRecord {
	day: number;
	volume: string;
	usd: number;
}

interface Report {
	date: string;
	weeklyData: DataRecord[];
}

const command: CommandInterface = {
	name: CLI_ARGS.commands.report,
	description: `Run a volume report for a specified amount of time`,
	execute: async (args: ArgumentsInterface): Promise<void> => {
		const intervalArg = args.commandValues[0] || '1-week';
		
		const regex = /^(\d+)\s*-?\s*(day|week|month|year)s?$/i;
		const match = intervalArg.match(regex);

		if (!match) {
			console.error(`Invalid interval format. Use something like '2-days', '1-week', or '1-year'.`);
			return;
		}

		console.log(clc.blackBright('UCM Volume Report'));

		const count = parseInt(match[1], 10);
		const unit = match[2].toLowerCase();

		const unitMapping: { [key: string]: number } = {
			day: 1,
			week: 7,
			month: 30,
			year: 365,
		};

		const permaweb = Permaweb.init({ ao: connect({ MODE: 'legacy' }) });

		try {
			const arweaveResponse = await fetch(ENDPOINTS.arweave);
			const currentHeight = (await arweaveResponse.json()).height;

			console.log(clc.blackBright(`Current Height: ${formatCount(currentHeight.toString())}\n`));

			const days = count * unitMapping[unit];
			console.log(`Generating report for the last ${clc.yellow(`${days} day(s)`)}...`);
	
			const now = new Date();
			const startDate = new Date(now.getTime() - days * 24 * 60 * 60 * 1000);
			const endDate = now;
	
			const formatDate = (date: Date) => date.toISOString().slice(0, 10);
			console.log(`Report period: ${clc.cyan(formatDate(startDate))} to ${clc.cyan(formatDate(endDate))}`);

			const baseTags = [
				{ name: 'Action', values: ['Credit-Notice'] },
				{ name: 'X-Order-Action', values: ['Create-Order'] },
				{ name: 'Data-Protocol', values: ['ao'] },
				{ name: 'Type', values: ['Message'] },
				{ name: 'Variant', values: ['ao.TN.1'] },
			];

			const spinner = new CliSpinner('Getting total order count...');

			const orderData = await permaweb.getGQLData({
				tags: [...baseTags],
				recipients: ['hqdL4AZaFZ0huQHbAsYxdTwG6vpibK7ALWKNzmWaD4Q'],
				minBlock: currentHeight - days * DAILY_HEIGHT_INTERVAL,
				maxBlock: currentHeight
			});

			spinner.stop();
			console.log(`Total order count: ${clc.green(orderData?.count ? formatCount(orderData.count.toString()) : 'N/A')}\n`);

			console.log(clc.blackBright('Getting price data...'));
			const arweavePriceResponse = await fetch(ENDPOINTS.arweavePrice);
			const arweavePrice = (await arweavePriceResponse.json()).arweave.usd;

			console.log(clc.blackBright('Getting GQL Data...\n'));

			const weeklyData: DataRecord[] = [];
			for (let i = 0; i < days; i++) {
				const intervalEnd = currentHeight - (i * DAILY_HEIGHT_INTERVAL);
				const intervalStart = intervalEnd - DAILY_HEIGHT_INTERVAL;

				spinner.stop();
				console.log(`Day ${i + 1}: ${clc.blackBright(`Blocks ${formatCount(intervalStart.toString())} to ${formatCount(intervalEnd.toString())}`)}`);
				spinner.start();

				const purchaseData = await permaweb.getAggregatedGQLData({
					tags: [
						...baseTags,
						{ name: 'X-Dominant-Token', values: ['xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'] }
					],
					recipients: ['hqdL4AZaFZ0huQHbAsYxdTwG6vpibK7ALWKNzmWaD4Q'],
					minBlock: intervalStart,
					maxBlock: intervalEnd
				}, (message: string) => {
					if (message.includes('Pages to fetch')) {
						spinner.stop();
						console.log(clc.blackBright(message))
						spinner.start();
					}
					else spinner.setMessage(message)
				});

				let totalSwap = BigInt(0);
				if (purchaseData) {
					for (const result of purchaseData) {
						const quantity = getTagValue(result.node.tags, 'Quantity');
						if (quantity) totalSwap += BigInt(quantity);
					}
				}
				const convertedAmount = totalSwap / BigInt(Math.pow(10, 12));
				const usdValue = parseFloat(convertedAmount.toString()) * arweavePrice;

				weeklyData.push({
					day: days - i,
					volume: convertedAmount.toString(),
					usd: usdValue
				});
				console.log('\n');
			}

			spinner.stop();
			let totalSwapValue = BigInt(0);
			let totalUsdValue = Number(0);
			console.log(`\n${clc.blackBright('Volume Summary')}`);
			weeklyData.length > 0 ? (weeklyData.reverse()).forEach(record => {
				totalSwapValue += BigInt(record.volume);
				totalUsdValue += record.usd;
				console.log(`Day ${record.day}: ${clc.green(formatCount(record.volume))} wAR, ${clc.green(formatCount(record.usd.toString()))} USD`);
			}) : console.log('-');

			console.log(`\n${clc.blackBright('Totals')}`);
			console.log(`${clc.green(formatCount(totalSwapValue.toString()))} wAR`);
			console.log(`${clc.green(formatCount(totalUsdValue.toString()))} USD`);
			console.log('\n');

			await exportWeeklyReportData({
				date: new Date().toISOString(),
				weeklyData
			}, days);

		} catch (e: any) {
			log(e.message ?? 'Error running report', 1);
		}
	}
};

export default command;

async function exportWeeklyReportData(report: Report, intervals: number): Promise<void> {
	const reportsDir = './reports';
	if (!fs.existsSync(reportsDir)) {
		fs.mkdirSync(reportsDir, { recursive: true });
	}
	
	const reportEndDate = new Date(report.date);
	const reportStartDate = new Date(reportEndDate);
	reportStartDate.setDate(reportStartDate.getDate() - (intervals - 1));
	
	const formatDate = (date: Date) => date.toISOString().slice(0, 10);
	const dateRangeStr = `${formatDate(reportStartDate)}_${formatDate(reportEndDate)}`;
	
	const timestamp = Date.now();
	const jsonPath = `${reportsDir}/volume-report-${dateRangeStr}-${timestamp}.json`;
	const chartPath = `${reportsDir}/volume-report-chart-${dateRangeStr}-${timestamp}.png`;
	
	fs.writeFileSync(jsonPath, JSON.stringify(report, null, 2), 'utf-8');
	console.log(clc.blackBright(`Report data exported to ${jsonPath}`));
	
	const latestData = report.weeklyData;
	const labels = latestData.map(record => `Day ${record.day}`);
	const volumes = latestData.map(record => parseFloat(record.volume));
	const usdValues = latestData.map(record => record.usd);

	const qc = new QuickChart();
	qc.setConfig({
		type: 'line',
		data: {
			labels: labels,
			datasets: [
				{
					label: 'Wrapped AR Swapped',
					data: volumes,
					borderColor: '#006DFF',
					fill: false,
				},
				{
					label: 'USD Volume',
					data: usdValues,
					borderColor: '#71C9A4',
					fill: false,
				},
			],
		},
		options: {
			title: {
				display: true,
				text: `Volume Report (${dateRangeStr})`,
			},
		},
	})
		.setWidth(800)
		.setHeight(400)
		.setBackgroundColor('#FFFFFF');

	try {
		const chartBuffer = await qc.toBinary();
		fs.writeFileSync(chartPath, chartBuffer);
		console.log(clc.blackBright(`Chart exported to ${chartPath}`));
	} catch (error) {
		console.error('Error generating chart:', error);
	}
}