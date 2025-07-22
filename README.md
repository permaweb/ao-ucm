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
   lua tests.lua
   ```
