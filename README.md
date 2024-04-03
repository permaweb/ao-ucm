# Universal Content Marketplace (UCM) AO Process

## Overview

The Universal Content Marketplace (UCM) is a protocol built on the permaweb designed to enable trustless exchange of atomic assets. It empowers creators and users to interact, trade, and transact with any form of digital content, from images and music to videos, papers, components, and even applications.

## How it works

The UCM functions by accepting a deposit from a buyer or seller and fulfilling orders based on the swap pairs and quantities that are later passed in. Here is a list of actions that take place to complete a UCM order.

1. A user deposits (transfers) their tokens to the UCM.
2. The token process issues a **Credit-Notice** to the UCM and a **Debit-Notice** back to the user.
3. The UCM **Credit-Notice Handler** adds the **Deposit (Transfer) Message ID** as well as **Token Quantity** to a desposits table.
4. When the deposit is complete, the user can call **Create-Order** in the UCM and pass the same **Deposit (Transfer) Message ID**.
5. The UCM uses the **Deposit (Transfer) Message ID** to ensure the original transfer is valid, and then matches and fulfills orders based on the input sent from the user. The order creation input includes the swap pair to execute on, as well as the quantity of tokens and price of tokens if the order is a limit order.

### Creating orders

#### AOS

###### Deposit (Transfer)

```lua
Send({ 
	Target = <Token-Process>, 
	Tags = { Action = 'Transfer' }, 
	Data = '{"Recipient": <UCM-Process>, "Quantity": <Quantity> }' 
})
```

###### Create-Order

```lua
Send({
	Target = <UCM-Process>, 
	Tags = { Action = 'Create-Order' }, 
	Data = '{"Pair": <Swap-Pair>, "DepositTxId": <DepositTxId>, "Quantity": <Quantity>, "Price": <Price> }'
})
```

#### NodeJS

###### Deposit (Transfer)

```js
const depositTxId = await message({ 
	process: <Token-Process>,
	tags: [{ name: 'Action', value: 'Transfer' }],
	signer: createDataItemSigner(wallet),
	data: {
		Recipient: <UCM-Process>,
		Quantity: <Quantity>
	}
 })
```

###### Create-Order

```js
const orderTxId = await message({ 
	process: <UCM-Process>,
	tags: [{ name: 'Action', value: 'Create-Order' }],
	signer: createDataItemSigner(wallet),
	data: {
		Pair: <Swap-Pair>,
		DepositTxId: depositTxId,
		Quantity: <Quantity>,
		Price: <Price>
	}
 })
```