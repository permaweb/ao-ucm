import { before, beforeEach, describe, it } from "node:test";
import { MarketplaceProcess } from "../utils/marketplace_process";
import { LocalAO, createLocalProcess } from "utils/local_ao";
import { AOProcess } from "@ar.io/sdk";
import assert from "node:assert";
import { BUNDLED_MARKETPLACE_SOURCE_CODE, TEST_SIGNER } from "utils/constants";


describe('Info', () => {
	let marketplaceProcess: MarketplaceProcess;
	let ao_mock: LocalAO


	// create a new process and mock before the tests
	before(async ()=> {
		const process = await createLocalProcess({processId: "my-marketplace-process-".padEnd(43, '1'), lua: BUNDLED_MARKETPLACE_SOURCE_CODE});
		ao_mock = process.ao as any as LocalAO;
		marketplaceProcess = new MarketplaceProcess({ process: new AOProcess({ao: process.ao, processId: process.processId}) });
	})

	beforeEach(async ()=> {
		// clear the current memory and resultsCache of the mock before each new test
		await ao_mock.reset();
	})

	it('should return the info', async () => {
		// AO Process example, this has internal tooling to check errors, json parse message bodies, etc
		const info = await marketplaceProcess.info();
		console.dir({info}, {depth: null});
		assert(info, 'Info should be defined');

		// Manual dryrun example, this is a direct call to the aos handle function and will return the whole result object
		const dryrunResult = await marketplaceProcess.process.ao.dryrun({
			tags: [{ name: 'Action', value: 'Info' }]
		});
		console.dir({dryrun: dryrunResult}, {depth: null});
		assert(dryrunResult, 'Dryrun should be defined');

		// example using process.send (again uses internal tooling to check errors, json parse message bodies, etc)
		const { id, result } = await marketplaceProcess.process.send({
			tags: [{ name: "Action", value: "Info"}],
			signer: TEST_SIGNER
		})
		console.dir({id, result}, {depth: null});
		assert(id, 'Id should be defined');
		assert(result, 'Result should be defined');

		// example using process.ao.message (this is a direct call to the aos handle function and will return the message id)
		const messageId = await marketplaceProcess.process.ao.message({
			tags: [{ name: "Action", value: "Info"}],
			signer: TEST_SIGNER
		})
		console.dir({messageId}, {depth: null});
		assert(messageId, 'Message id should be defined');

		// example using process.ao.result (this is a direct call to the aos handle function and will return the message result)
		// the localAO class maintains a resultsCache that will return the result if it has been called before
		const msgResult = await marketplaceProcess.process.ao.result({
			message: messageId,
			process: marketplaceProcess.process.processId
		})
		console.dir({msgResult}, {depth: null});
		assert(msgResult, 'Result should be defined');
	});
});