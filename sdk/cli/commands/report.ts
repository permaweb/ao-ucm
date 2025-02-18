import clc from 'cli-color';
import fs from 'fs';
import { Chart, registerables } from 'chart.js';
import { createCanvas } from 'canvas';

import { connect } from '@permaweb/aoconnect';
import Permaweb from '@permaweb/libs';

import { CLI_ARGS, DAILY_HEIGHT_INTERVAL, ENDPOINTS } from '../helpers/config.ts';
import { ArgumentsInterface, CommandInterface, DataRecord, Report } from '../helpers/types.ts';
import { CliSpinner, formatCount, getTagValue, log } from '../helpers/utils.ts';

Chart.register(...registerables);

const command: CommandInterface = {
	name: CLI_ARGS.commands.report,
	description: `Run a volume report for a specified amount of time`,
	execute: async (args: ArgumentsInterface): Promise<void> => {
		const intervalArg = args.commandValues[0] || '1-week';

		const regex = /^(\d+)\s*-?\s*(day|week|month|year)s?$/i;
		const match = intervalArg.match(regex);

		if (!match) {
			console.error(`Invalid interval format. Use something like '2-days', '1-week', or '1-month'.`);
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

			const intervalData: DataRecord[] = [];
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

				intervalData.push({
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
			intervalData.length > 0 ? (intervalData.reverse()).forEach(record => {
				totalSwapValue += BigInt(record.volume);
				totalUsdValue += record.usd;
				console.log(`Day ${record.day}: ${clc.green(formatCount(record.volume))} wAR, ${clc.green(formatCount(record.usd.toString()))} USD`);
			}) : console.log('-');

			console.log(`\n${clc.blackBright('Totals')}`);
			console.log(`${clc.green(formatCount(totalSwapValue.toString()))} wAR`);
			console.log(`${clc.green(formatCount(totalUsdValue.toString()))} USD`);
			console.log('\n');

			await exportReportData({
				date: new Date().toISOString(),
				intervalData
			}, days);

		} catch (e: any) {
			log(e.message ?? 'Error running report', 1);
		}
	}
};

export default command;

async function exportReportData(report: Report, intervals: number): Promise<void> {
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
	const updatedChartPath = `${reportsDir}/volume-report-chart-${dateRangeStr}-${timestamp}.png`;

	const latestData = report.intervalData;
	const labels = latestData.map(record => `Day ${record.day}`);
	const volumes = latestData.map(record => parseFloat(record.volume));
	const usdValues = latestData.map(record => record.usd);

	const width = 800;
	const height = 400;

	const canvas = createCanvas(width, height);
	const ctx = canvas.getContext('2d');

	const configuration = {
		type: 'line',
		data: {
			labels: labels, // Use your existing data
			datasets: [
				{
					label: 'Wrapped AR Swapped',
					data: volumes,
					borderColor: '#006DFF',
					backgroundColor: 'rgba(0, 109, 255, 0.2)',
					fill: true,
				},
				{
					label: 'USD Volume',
					data: usdValues,
					borderColor: '#71C9A4',
					backgroundColor: 'rgba(113, 201, 164, 0.2)',
					fill: true,
				},
			],
		},
		options: {
			title: {
				display: true,
				text: `UCM Volume (${formatDate(reportStartDate)} to ${formatDate(reportEndDate)})`,
			},
			legend: {
				display: true,
			},
			layout: {
				padding: {
					top: 20,
					right: 20,
					bottom: 25,
					left: 20,
				},
			},
		},
	};

	new Chart(ctx as any, configuration as any);

	// Export the chart as an image
	const buffer = canvas.toBuffer('image/png');
	fs.writeFileSync('./chart.png', buffer);
	console.log('Chart saved as chart.png');

	try {
		const days = report.intervalData.map(record => `Day ${record.day}`);
		const volumes = report.intervalData.map(record => parseFloat(record.volume));
		const usdValues = report.intervalData.map(record => record.usd);

		console.log('Blue line: Volume (wAR)');
		console.log('Green line: USD Volume\n');

		const asciichart = await import('asciichart');

		function interpolate(data: any) {
			const interpolated = [];
			for (let i = 0; i < data.length - 1; i++) {
				interpolated.push(data[i]);
				interpolated.push((data[i] + data[i + 1]) / 2);
			}
			interpolated.push(data[data.length - 1]);
			return interpolated;
		}

		const volumesInterpolated = interpolate(volumes);
		const usdValuesInterpolated = interpolate(usdValues);

		const config = {
			height: 10,
			colors: [
				asciichart.blue,
				asciichart.green,
			]
		};

		console.log(asciichart.plot([volumesInterpolated, usdValuesInterpolated], config));

	} catch (error) {
		console.error('Error generating chart:', error);
	}
}