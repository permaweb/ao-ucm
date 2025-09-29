import { AOProcess } from "@ar.io/sdk";
import { LocalAO, createLocalProcess } from "./local_ao";

export class MarketplaceProcess {

	process: AOProcess;

	constructor({process}:{process: AOProcess}) {
		this.process = process;
	}

	async info() {
		return await this.process.read({
			tags: [{ name: 'Action', value: 'Info' }]
		});
	}
}