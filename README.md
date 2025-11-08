# Universal Content Marketplace (UCM) AO Process

## Overview

The Universal Content Marketplace (UCM) is a protocol built on the permaweb designed to enable trustless exchange of atomic assets. It empowers creators and users to interact, trade, and transact with any form of digital content, from images and music to videos, papers, components, and even applications.

## How it works

The UCM functions by accepting a deposit from a buyer or seller and fulfilling orders based on the swap pair, quantity, and possibly price that are passed along with the deposit. The orderbook maintains two sides for each trading pair:

- **Asks** (sell orders): Users selling the base token for the quote token
- **Bids** (buy orders): Users buying the base token with the quote token

The order side is automatically determined by which token is transferred (the dominant token). If the dominant token is the base token, it creates an Ask. If the dominant token is the quote token, it creates a Bid.

### Order Execution Flow

1. A user deposits (transfers) their tokens to the UCM. The user must add additional tags to the **Transfer Message** which are forwarded to the UCM process and used to create the order.
2. The token process issues a **Credit-Notice** to the UCM and a **Debit-Notice** to the user.
3. The UCM **Credit-Notice Handler** validates the required tags and determines the order side based on the dominant token.
4. The UCM processes the order:
   - **Market orders** (no price specified): Immediately matched against the best available orders on the opposite side
   - **Limit orders** (price specified): Added to the orderbook and matched when a suitable opposite order arrives
5. When orders match:
   - The incoming order is matched against the best-priced orders on the opposite side
   - Tokens are transferred between the two parties (minus a 0.5% fee)
   - The orderbook is updated to reflect remaining quantities
   - A VWAP (volume-weighted average price) is calculated for the executed trades

#### Additional Tags

| Name                        | Value        | Required |
| :-------------------------- | :----------- | :------- |
| X-Order-Action              | Create-Order | Yes      |
| X-Base-Token                | BASE_TOKEN   | Yes      |
| X-Quote-Token               | QUOTE_TOKEN  | Yes      |
| X-Base-Token-Denomination   | BASE_DENOM   | Yes      |
| X-Quote-Token-Denomination  | QUOTE_DENOM  | Yes      |
| X-Dominant-Token            | DOMINANT_TOKEN | Yes    |
| X-Swap-Token                | SWAP_TOKEN   | Yes      |
| X-Price                     | UNIT_PRICE   | No (for limit orders) |
| X-Transfer-Denomination     | TOKEN_DENOMINATION | No |
| X-Group-ID                  | MESSAGE_GROUP_ID | Yes  |

### Creating orders

#### AOS

###### Deposit (Transfer)

```lua
Send({
	Target = DOMINANT_TOKEN,
	Action = 'Transfer'
	Tags = {
		'Recipient' = UCM_PROCESS,
		'Quantity' = ORDER_QUANTITY,
		'X-Order-Action' = 'Create-Order',
		'X-Base-Token' = BASE_TOKEN,
		'X-Quote-Token' = QUOTE_TOKEN,
		'X-Base-Token-Denomination' = BASE_DENOM,
		'X-Quote-Token-Denomination' = QUOTE_DENOM,
		'X-Dominant-Token' = DOMINANT_TOKEN,
		'X-Swap-Token' = SWAP_TOKEN,
		'X-Price' = UNIT_PRICE, -- Optional: for limit orders
		'X-Transfer-Denomination' = TOKEN_DENOMINATION, -- Optional
		'X-Group-ID' = MESSAGE_GROUP_ID,
	}
})
```

#### NodeJS

###### Deposit (Transfer)

```js
const MESSAGE_GROUP_ID = Date.now().toString();

const tags = [
	{ name: 'Recipient', value: ORDERBOOK_ID },
	{ name: 'Quantity', value: ORDER_QUANTITY },
	{ name: 'X-Order-Action', value: 'Create-Order' },
	{ name: 'X-Base-Token', value: BASE_TOKEN },
	{ name: 'X-Quote-Token', value: QUOTE_TOKEN },
	{ name: 'X-Base-Token-Denomination', value: BASE_DENOM },
	{ name: 'X-Quote-Token-Denomination', value: QUOTE_DENOM },
	{ name: 'X-Dominant-Token', value: DOMINANT_TOKEN },
	{ name: 'X-Swap-Token', value: SWAP_TOKEN },
	{ name: 'X-Group-ID', value: MESSAGE_GROUP_ID },
];

// Optional: Add price for limit orders (omit for market orders)
if (unitPrice) {
	tags.push({ name: 'X-Price', value: unitPrice });
}

// Optional: Add denomination
if (denomination) {
	tags.push({ name: 'X-Transfer-Denomination', value: denomination });
}

// Send transfer to dominant token
await permaweb.sendMessage({
	processId: DOMINANT_TOKEN,
	action: 'Transfer',
	tags: tags
});
```
