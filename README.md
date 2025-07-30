# ARnS Marketplace AO Process

## Overview

The ARnS Marketplace is a protocol built on the permaweb designed to enable trustless exchange of ARNS tokens. It empowers users to interact, trade, and transact with ARNS domain tokens.

## How it works

The ARnS Marketplace functions by accepting a deposit from a buyer or seller and fulfilling orders based on the swap pair, quantity, and possibly price that are passed along with the deposit. Here is a list of actions that take place to complete an ARnS Marketplace order.

1. A user deposits (transfers) their tokens to the ARnS Marketplace. The user will also have to add additional tags to the **Transfer Message** which are forwarded to the ARnS Marketplace process and will be used to create the order.
2. The token process issues a **Credit-Notice** to the ARnS Marketplace and a **Debit-Notice** to the user.
3. The ARnS Marketplace **Credit-Notice Handler** determines if the required tags are present in order to create the order.
4. The ARnS Marketplace uses the forwarded tags passed to the **Transfer Handler** to submit an order to the orderbook. The order creation input includes the swap pair to execute on, as well as the quantity of tokens and price of tokens if the order is a limit order.

#### Additional Tags

| Name           | Value        |
| :------------- | :----------- |
| X-Order-Action | Create-Order |
| X-Swap-Token   | SWAP_TOKEN   |
| X-Price        | UNIT_PRICE   |

### Creating orders

#### AOS

###### Deposit (Transfer)

```lua
Send({
	Target = TOKEN_PROCESS,
	Action = 'Transfer'
	Tags = {
		'Recipient' = ARNS_MARKETPLACE_PROCESS,
		'Quantity' = ORDER_QUANTITY,
		'X-Order-Action' = 'Create-Order'
		'X-Swap-Token' = SWAP_TOKEN,
		'X-Price' = UNIT_PRICE,
		'X-Transfer-Denomination' = TOKEN_DENOMINATION,
	}
})
```

#### NodeJS

###### Deposit (Transfer)

```js
const response = await messageResults({
	processId: arProvider.profile.id,
	action: 'Transfer',
	wallet: arProvider.wallet,
	tags: transferTags,
	data: {
		Target: dominantToken,
		Recipient: recipient,
		Quantity: calculatedQuantity,
	},
	responses: ['Transfer-Success', 'Transfer-Error'],
	handler: 'Create-Order',
});
```

```js
const response = await message({
	process: TOKEN_PROCESS,
	signer: createDataItemSigner(global.window.arweaveWallet),
	tags: [
		{ name: 'Action', value: 'Transfer' },
		{ name: 'Recipient', value: ARNS_MARKETPLACE_PROCESS },
		{ name: 'Quantity', value: ORDER_QUANTITY },
		{ name: 'X-Order-Action', value: 'Create-Order' },
		{ name: 'X-Swap-Token', value: SWAP_TOKEN },
		{ name: 'X-Price', value: ORDER_PRICE },
		{ name: 'X-Transfer-Denomination', value: TOKEN_DENOMINATION },
	],
});
```

## Testing

### Prerequisites

Before running the tests, ensure you have the following installed:

1. **Lua 5.4+**: Install Lua for your operating system
   - **macOS**: `brew install lua`
   - **Ubuntu/Debian**: `sudo apt-get install lua5.4`
   - **CentOS/RHEL**: `sudo yum install lua54`
   - **Windows**: Download from [Lua.org](https://www.lua.org/download.html) or use [Chocolatey](https://chocolatey.org/): `choco install lua`

2. **LuaRocks** (Lua package manager): Install for your operating system
   - **macOS**: `brew install luarocks`
   - **Ubuntu/Debian**: `sudo apt-get install luarocks`
   - **CentOS/RHEL**: `sudo yum install luarocks`
   - **Windows**: Download from [LuaRocks.org](https://luarocks.org/) or use Chocolatey: `choco install luarocks`

3. **Required Lua modules**: Install the dependencies
   ```bash
   luarocks install bint
   luarocks install json-lua
   ```

### Running Tests

To run the test suite:

1. Navigate to the tests directory:
   ```bash
   cd tests
   ```

2. Run the tests:
   ```bash
   lua ucm_tests.lua
   ```

## Development

### SDK Development

The SDK provides TypeScript interfaces for interacting with the marketplace:

```bash
cd sdk
npm install
npm run build
```

### Toolkit Development

The toolkit provides development utilities:

```bash
cd toolkit
npm install
npm run build
```

## Deployment

### Prerequisites

Before deploying, ensure you have:

1. **AO SDK installed**: Install the AO command line tools
   ```bash
	npm i -g https://get_ao.g8way.io
   ```

2. **Wallet file**: An Arweave wallet JSON file for deployment. You can generate one simply by running `aos` in terminal. It should be created in `~/.aos.json`.

3. **Environment variables**: Look for `CHANGEME` in code to change required variables:
```
# This is the activity process address.
ACTIVITY_PROCESS= 

# This is the ARIO token process address.
ARIO_TOKEN_PROCESS_ID=
```

### Deployment Steps

1. **Start CLI**:
   ```bash
   aos --wallet /path/to/your/wallet.json
   ```

2. **Deploy the code**:
	```bash
	user@aos-2.0.4[Inbox:1]> .load src/bundle_ucm.lua
	```
	If the code is correct, the CLI will show the standard prompt.

### Deployment Notes

- Use `src/bundle_ucm.lua` which is a self-contained version with all dependencies.

## Project Structure

This project consists of several components organized into different directories:

### Core Process Files (`src/`)

#### Main Process Files
- **`process.lua`** - Main entry point for the ARnS Marketplace process. Handles message routing, validation, and core marketplace functionality including order creation, credit notices, and basic process operations.

- **`ucm.lua`** - ANT Marketplace core logic. Contains the main marketplace functions including order book management, pair indexing, order creation, and error handling. This is the heart of the marketplace functionality.

- **`activity.lua`** - Activity tracking and reporting system. Manages order history, executed orders, cancelled orders, and provides activity queries with filtering capabilities by address, date range, and asset IDs.

- **`utils.lua`** - Utility functions used throughout the project. Includes address validation, amount validation, JSON message decoding, pair data validation, fee calculations, and table printing utilities.

#### Bundle Files (Combined Modules)
- **`bundle_ucm.lua`** - Self-contained bundle of the ANT Marketplace with all dependencies included. This is a standalone version that can be deployed independently.

- **`bundle_activity_collection.lua`** - Bundled activity collection system for tracking and managing marketplace activity data.

- **`bundle_activity_asset.lua`** - Bundled asset-specific activity tracking system for monitoring individual asset trading activity.

### SDK (`sdk/`)

The SDK provides TypeScript/JavaScript interfaces for interacting with the ARnS Marketplace:

- **`package.json`** - SDK package configuration with dependencies for Arweave and Permaweb libraries
- **`build.js`** - Build script for compiling the SDK
- **`tsconfig.json`** - TypeScript configuration for the SDK
- **`src/`** - Source code for the SDK including services and helpers
- **`bin/`** - Binary executables for the SDK

### Toolkit (`toolkit/`)

Development and testing tools for the marketplace:

- **`package.json`** - Toolkit package configuration with AO Connect dependencies
- **`tsconfig.json`** - TypeScript configuration for the toolkit
- **`src/index.ts`** - Main toolkit implementation for development and testing utilities

### Testing (`tests/`)

- **`tests.lua`** - Comprehensive test suite for the marketplace functionality
- **`node/`** - Node.js based tests for the SDK and toolkit components

### Configuration Files

- **`.editorconfig`** - Editor configuration for consistent coding style
- **`.gitignore`** - Git ignore rules for the project
- **`spec.md`** - Detailed specification document for the ARnS Marketplace protocol
