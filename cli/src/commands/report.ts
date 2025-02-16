import clc from 'cli-color';
import fs from 'fs';
import QuickChart from 'quickchart-js';

import { connect } from '@permaweb/aoconnect';
import Permaweb from '@permaweb/libs';

import { CLI_ARGS, DAILY_HEIGHT_INTERVAL, ENDPOINTS } from '../helpers/config';
import { ArgumentsInterface, CommandInterface } from '../helpers/types';
import { CliSpinner, formatCount, getTagValue, log } from '../helpers/utils';

interface WeeklyDataRecord {
	day: number;
	volume: string;
	usd: number;
}

interface WeeklyReport {
	date: string;
	weeklyData: WeeklyDataRecord[];
}

const command: CommandInterface = {
	name: CLI_ARGS.commands.report,
	description: `Run a weekly report on UCM activity`,
	execute: async (args: ArgumentsInterface): Promise<void> => {
		const permaweb = Permaweb.init({ ao: connect({ MODE: 'legacy' }) });
		console.log(clc.blackBright('UCM Volume Report'));

		try {
			const arweaveResponse = await fetch(ENDPOINTS.arweave);
			const currentHeight = (await arweaveResponse.json()).height;

			const intervals = 2;
			console.log(`Building report for the last ${intervals} days...\n`);

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
				minBlock: currentHeight - intervals * DAILY_HEIGHT_INTERVAL,
				maxBlock: currentHeight
			});

			spinner.stop();
			console.log(`Total order count: ${clc.green(orderData?.count ? formatCount(orderData.count.toString()) : 'N/A')}\n`);

			console.log(clc.blackBright('Getting price data...'));
			const arweavePriceResponse = await fetch(ENDPOINTS.arweavePrice);
			const arweavePrice = (await arweavePriceResponse.json()).arweave.usd;

			console.log(clc.blackBright('Getting GQL Data...\n'));
			const weeklyData: WeeklyDataRecord[] = [];
			for (let i = 0; i < intervals; i++) {
				const intervalEnd = currentHeight - (i * DAILY_HEIGHT_INTERVAL);
				const intervalStart = intervalEnd - DAILY_HEIGHT_INTERVAL;
				
				spinner.stop();
				console.log(`Day ${i + 1}: Blocks ${intervalStart} to ${intervalEnd}`);
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
					day: intervals - i,
					volume: convertedAmount.toString(),
					usd: usdValue
				});
				console.log('\n');
			}

			spinner.stop();
			console.log(`\n${clc.blackBright('Weekly Report Volume Summary')}`);
			(weeklyData.reverse()).forEach(record => {
				console.log(`Day ${record.day}: ${clc.green(formatCount(record.volume))} wAR, ${clc.green(formatCount(record.usd.toString()))} USD`);
			});
			console.log('\n');

			// If --export flag is provided, export the weekly report data and generate a chart.
			if (true) { // args.argv.export
				await exportWeeklyReportData({
					date: new Date().toISOString(),
					weeklyData
				});
			}
		} catch (e: any) {
			log(e.message ?? 'Error running report', 1);
		}
	},
};

export default command;

async function exportWeeklyReportData(report: WeeklyReport): Promise<void> {
	// Ensure the reports directory exists
	const reportsDir = './reports';
	if (!fs.existsSync(reportsDir)) {
		fs.mkdirSync(reportsDir, { recursive: true });
	}

	// Use the report date as the end date, and assume the report covers 7 days
	const reportEndDate = new Date(report.date);
	const reportStartDate = new Date(reportEndDate);
	reportStartDate.setDate(reportStartDate.getDate() - 6); // 7-day report

	// Helper to format dates as YYYY-MM-DD
	const formatDate = (date: Date) => date.toISOString().slice(0, 10);
	const dateRangeStr = `${formatDate(reportStartDate)}--${formatDate(reportEndDate)}`;

	// Generate unique file names by appending a timestamp
	const timestamp = Date.now();
	const jsonPath = `${reportsDir}/weekly-report-${dateRangeStr}-${timestamp}.json`;
	const chartPath = `${reportsDir}/weekly-report-chart-${dateRangeStr}-${timestamp}.png`;

	// Write the report JSON to a new file
	fs.writeFileSync(jsonPath, JSON.stringify(report, null, 2), 'utf-8');
	console.log(clc.blackBright(`Exported weekly report data to ${jsonPath}`));

	// Prepare data for the line chart using the latest weekly data
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
				text: `Weekly Volume Report (${dateRangeStr})`,
			},
		},
	})
		.setWidth(800)
		.setHeight(400)
		.setBackgroundColor('#FFFFFF');

	try {
		const chartBuffer = await qc.toBinary();
		fs.writeFileSync(chartPath, chartBuffer);
		console.log(clc.blackBright(`Exported weekly chart to ${chartPath}`));
	} catch (error) {
		console.error('Error generating weekly chart:', error);
	}
}