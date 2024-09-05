# Universal Content Marketplace (UCM)

**Status:** Draft

**Version:** 0.0.1

**Authors:** Nick Juliano (nick@arweave.org)

## Introduction

The **Universal Content Marketplace (UCM)** protocol facilitates the trustless exchange of atomic digital assets on the permaweb. It supports trading between any form of digital content, such as artwork, documents, or media files, using a decentralized order book system. UCM also incentivizes users with **PIXL tokens**, which are distributed based on purchasing activity, including tracked streaks for consecutive purchases.

This specification describes the UCM's functionality, including order creation, execution, and integration of PIXL token incentives.

---

### Key Components

1. **Atomic Assets**: Unique, indivisible digital items representing content on the permaweb.
2. **PIXL Token**: A reward token that incentivizes purchasing activity within UCM.
3. **Order Book**: The data structure that stores active buy and sell orders for trading assets.
4. **Buy Streaks**: A mechanism that tracks users' consecutive daily purchases, rewarding them with PIXL tokens.
5. **Swap Token**: A token used in exchange for atomic assets. The default swap token is defined as `DEFAULT_SWAP_TOKEN`.

---

### Core Data Structures

#### 1. **Order Book Entry**
Each pair of tokens traded is associated with an order book entry containing multiple orders.

```lua
Orderbook = {
    Pair = [TokenId, TokenId],
    Orders = {
        Id,
        Creator,
        Quantity,
        OriginalQuantity,
        Token,
        DateCreated,
        Price? (optional for market orders)
    }[]
}[]
```

#### 2. **Order**
Each order represents a user's intent to buy or sell a specific quantity of atomic assets at a certain price (limit orders) or at the market price (market orders).

---

### Functions

#### 1. **getPairIndex**
Finds the index of the token pair in the order book. This allows the system to efficiently look up and manage pairs of assets being traded.

#### 2. **createOrder**
Handles the creation of both market and limit orders. It:
- Validates the token pair and ensures the quantities and prices are positive integers.
- Executes the order by finding matches in the order book, fulfilling it as much as possible.
- Updates the order book with any remaining quantity from the order (in the case of limit orders).
- Notifies the creator about the success or failure of the order.
- Records matches and updates the executed orders list.

#### 3. **handleError**
Handles error reporting and, if applicable, refunds the sender’s tokens in case of an invalid transaction.

#### 4. **executeBuyback**
This feature enables the automatic execution of PIXL token buybacks when there is sufficient quantity available in the order book for the `PIXL_PROCESS`.

---

### Order Types

- **Market Orders**: Executed at the best available price in the order book. The protocol attempts to fill the entire order quantity based on existing limit orders.
- **Limit Orders**: Executed only if the market price meets the user's specified price. Any remaining unfilled quantity is added to the order book.

### Incentives and Tracking

#### 1. **PIXL Token Incentives**
When users purchase atomic assets, they are eligible to receive **PIXL tokens**. The system tracks buy streaks, which are awarded for consecutive daily purchases. Buy streaks are calculated by sending a request to the PIXL process during the order execution phase.

#### 2. **Volume-Weighted Average Price (VWAP)**
For every set of matched orders, the **VWAP** is computed and stored for reference. This provides a clear view of the average price of traded assets over time.

---

### Processes

#### 1. **ACTIVITY_PROCESS**
Handles updating of executed orders, logging them with their relevant details (such as quantity, price, and involved parties).

#### 2. **PIXL_PROCESS**
Performs the calculation of buy streaks and manages the allocation of PIXL tokens to buyers based on their activity.

---

### Example Workflow

1. **Order Creation**:
   - A user creates a new order to buy or sell an atomic asset.
   - The system checks for matching orders in the order book.
   - If there is a match, the order is fulfilled, and tokens are transferred between buyer and seller.
   - If there are no matching orders, the system adds the order to the order book (for limit orders).

2. **Order Matching**:
   - The order book matches the buy and sell orders, prioritizing those with the most favorable prices.
   - For market orders, the entire available quantity is filled as long as there are sufficient assets available in the order book.

3. **PIXL Token Reward**:
   - When an order is executed, the system calculates whether the user has maintained a buy streak.
   - If eligible, the user receives PIXL tokens as a reward for consistent activity.

---

### Fees

UCM captures a 0.5% fee. If the trade involves the $wAR token, the protocol purchases PIXL with the fee. It buys available orders, and if no “Sell” orders exist, it initiates a “Buy” order via a reverse Dutch auction. PIXL tokens received from these purchases are burned. The higher the trading volumes and marketplace fees, the more tokens are bought and burned.

---

### Error Handling

Errors in the system (such as invalid token pairs, insufficient quantities, or pricing issues) are caught by the `handleError` function, which returns any necessary tokens to the user and logs the error for further analysis.

---

### Conclusion

The Universal Content Marketplace (UCM) protocol is a decentralized marketplace built on the permaweb, enabling users to trade atomic assets while incentivizing participation through the PIXL token. Its robust order book system supports both market and limit orders, ensuring efficient and trustless exchanges of digital assets.