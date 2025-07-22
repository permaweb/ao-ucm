# ARNS Marketplace
## Introduction

The **ARNS Marketplace** protocol facilitates the trustless exchange of ARnS tokens using a decentralized order book system.

This specification describes the ARNS Marketplace's functionality, including order creation and execution.

---

### Key Components

1. **ARNS Tokens**: Unique tokens representing ARNS domains on the permaweb.
2. **Order Book**: The data structure that stores active buy and sell orders for trading ARNS tokens.
3. **Swap Token**: A token used in exchange for ARNS tokens. The default swap token is defined as `DEFAULT_SWAP_TOKEN`.

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
Each order represents a user's intent to buy or sell a specific quantity of ARNS tokens at a certain price (limit orders) or at the market price (market orders).

---

### Functions

#### 1. **getPairIndex**
Finds the index of the token pair in the order book. This allows the system to efficiently look up and manage pairs of ARNS tokens being traded.

#### 2. **createOrder**
Handles the creation of both market and limit orders. It:
- Validates the token pair and ensures the quantities and prices are positive integers.
- Executes the order by finding matches in the order book, fulfilling it as much as possible.
- Updates the order book with any remaining quantity from the order (in the case of limit orders).
- Notifies the creator about the success or failure of the order.
- Records matches and updates the executed orders list.

#### 3. **handleError**
Handles error reporting and, if applicable, refunds the sender's tokens in case of an invalid transaction.

---

### Order Types

- **Market Orders**: Executed at the best available price in the order book. The protocol attempts to fill the entire order quantity based on existing limit orders.
- **Limit Orders**: Executed only if the market price meets the user's specified price. Any remaining unfilled quantity is added to the order book.

### Tracking

#### 1. **Volume-Weighted Average Price (VWAP)**
For every set of matched orders, the **VWAP** is computed and stored for reference. This provides a clear view of the average price of traded ARNS tokens over time.

---

### Processes

#### 1. **ACTIVITY_PROCESS**
Handles updating of executed orders, logging them with their relevant details (such as quantity, price, and involved parties).

---

### Example Workflow

1. **Order Creation**:
   - A user creates a new order to buy or sell ARNS tokens.
   - The system checks for matching orders in the order book.
   - If there is a match, the order is fulfilled, and tokens are transferred between buyer and seller.
   - If there are no matching orders, the system adds the order to the order book (for limit orders).

2. **Order Matching**:
   - The order book matches the buy and sell orders, prioritizing those with the most favorable prices.
   - For market orders, the entire available quantity is filled as long as there are sufficient ARNS tokens available in the order book.

---

### Fees

ARNS Marketplace captures a 0.5% fee on trades.

---

### Error Handling

Errors in the system (such as invalid token pairs, insufficient quantities, or pricing issues) are caught by the `handleError` function, which returns any necessary tokens to the user and logs the error for further analysis.

---

### Conclusion

The ARNS Marketplace protocol is a decentralized marketplace built on the permaweb, enabling users to trade ARNS tokens. Its robust order book system supports both market and limit orders, ensuring efficient and trustless exchanges of ARNS tokens.