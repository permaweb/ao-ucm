local bint = require('.bint')(256)
local json = require('JSON')

local utils = require('utils')

local english_auction = {}

-- Initialize bid storage if it doesn't exist
if not EnglishAuctionBids then EnglishAuctionBids = {} end

-- Helper function to get auction bids for a specific order
local function getAuctionBids(orderId)
	if not EnglishAuctionBids[orderId] then
		EnglishAuctionBids[orderId] = {
			Bids = {},
			HighestBid = nil,
			HighestBidder = nil
		}
	end
	return EnglishAuctionBids[orderId]
end

-- Helper function to get existing auction bids (doesn't create if doesn't exist)
local function getExistingAuctionBids(orderId)
	return EnglishAuctionBids[orderId]
end

-- Helper function to validate auction is still active
local function isAuctionActive(expirationTime, currentTimestamp)
	return bint(expirationTime) > bint(currentTimestamp)
end

-- Helper function to validate bid amount
local function validateBidAmount(bidAmount, currentHighestBid)
	if not utils.checkValidAmount(bidAmount) then
		return false, 'Bid amount must be a positive integer'
	end
	
	if currentHighestBid and bint(bidAmount) <= bint(currentHighestBid) then
		return false, 'Bid must be higher than current highest bid'
	end
	
	return true, nil
end

-- Helper function to return previous highest bid
local function returnPreviousBid(orderId, previousBidder, previousAmount, biddingToken)
	if previousBidder and previousAmount and biddingToken then
		-- Send refund transfer to previous bidder
		ao.send({
			Target = biddingToken,
			Action = 'Transfer',
			Tags = {
				Recipient = previousBidder,
				Quantity = tostring(previousAmount)
			}
		})
		
		-- Notify previous bidder of refund
		ao.send({
			Target = previousBidder,
			Action = 'Bid-Returned',
			Tags = {
				Status = 'Success',
				OrderId = orderId,
				Amount = tostring(previousAmount),
				Message = 'Your previous bid has been returned as a higher bid was placed'
			}
		})
	end
end

-- Helper function to handle ANT token orders: we are buying ANT token, so we need to place bids on English auctions
function english_auction.handleAntOrder(args, validPair, pairIndex)
	-- Check if orderId is provided (required for bid identification)
	if not args.orderId then
		utils.handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = 'Order ID is required for bidding',
			Quantity = args.quantity,
			TransferToken = args.dominantToken,
			OrderGroupId = args.orderGroupId
		})
		return
	end
	
	local currentOrders = Orderbook[pairIndex].Orders
	local targetOrder = nil

	-- Find the English auction order to bid on
	for i, order in ipairs(currentOrders) do
		if order.Type == 'english' and order.Id == (args.requestedOrderId or args.orderId) then
			targetOrder = order
			break
		end
	end

	-- Check if the auction exists
	if not targetOrder then
		utils.handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = 'English auction not found',
			Quantity = args.quantity,
			TransferToken = args.dominantToken,
			OrderGroupId = args.orderGroupId
		})
		return
	end

	-- Check if auction has expired
	if not isAuctionActive(targetOrder.ExpirationTime, args.timestamp) then
		utils.handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = 'Auction has expired',
			Quantity = args.quantity,
			TransferToken = args.dominantToken,
			OrderGroupId = args.orderGroupId
		})
		return
	end

	-- Get existing auction bids for validation
	local targetAuctionId = args.requestedOrderId or args.orderId
	local existingBids = getExistingAuctionBids(targetAuctionId)
	
	-- Validate bid amount - use args.quantity for ARIO-dominant orders (buying ANT)
	local bidAmount = args.quantity -- The amount of ARIO tokens sent by the user
	
	local isValidBid, bidError = validateBidAmount(bidAmount, existingBids and existingBids.HighestBid or nil)
	
	if not isValidBid then
		utils.handleError({
			Target = args.sender,
			Action = 'Validation-Error',
			Message = bidError,
			Quantity = args.quantity,
			TransferToken = args.dominantToken,	
			OrderGroupId = args.orderGroupId
		})
		return
	end

	-- Get auction bids (only after validation passes)
	local auctionBids = getAuctionBids(targetAuctionId)
	
	-- Return previous highest bid if it exists
	if auctionBids.HighestBidder and auctionBids.HighestBid then
		returnPreviousBid(targetAuctionId, auctionBids.HighestBidder, auctionBids.HighestBid, args.dominantToken)
	end

	-- Store the new bid
	local newBid = {
		Bidder = args.sender,
		Amount = tostring(bidAmount), -- Use the quantity sent by user
		Timestamp = args.timestamp,
		OrderId = targetAuctionId
	}
	
	table.insert(auctionBids.Bids, newBid)
	
	-- Update highest bid
	auctionBids.HighestBid = tostring(bidAmount) -- Use the quantity sent by user
	auctionBids.HighestBidder = args.sender

	-- Send bid data to activity tracking process
	local bidDataSuccess, bidData = pcall(function()
		return json.encode({
			Bid = {
				OrderId = targetAuctionId,
				Bidder = args.sender,
				Amount = tostring(bidAmount), -- Use the quantity sent by user
				Timestamp = args.timestamp,
				DominantToken = args.dominantToken,
				SwapToken = args.swapToken,
				BidType = 'english_auction'
			}
		})
	end)

	ao.send({
		Target = ACTIVITY_PROCESS,
		Action = 'Update-Auction-Bids',
		Data = bidDataSuccess and bidData or ''
	})

	-- Notify sender of successful bid placement
	ao.send({
		Target = args.sender,
		Action = 'Bid-Success',
		Tags = {
			Status = 'Success',
			OrderId = targetAuctionId,
			Handler = 'Create-Order',
			DominantToken = args.dominantToken,
			SwapToken = args.swapToken,
			BidAmount = tostring(bidAmount), -- Use the quantity sent by user
			Message = 'Bid placed successfully on English auction!',
			['X-Group-ID'] = args.orderGroupId,
			OrderType = 'english'
		}
	})
end

-- Helper function to settle English auction
function english_auction.settleAuction(args)
	local orderId = args.orderId
	local auctionBids = getExistingAuctionBids(orderId)
	
	-- Check if auction has bids
	if not auctionBids or not auctionBids.HighestBidder then
		utils.handleError({
			Target = args.sender,
			Action = 'Settlement-Error',
			Message = 'No bids found for auction',
			Quantity = '0',
			TransferToken = nil,
			OrderGroupId = args.orderGroupId
		})
		return
	end

	-- Find the auction order
	local targetOrder = nil
	local targetOrderIndex = nil
	local targetPairIndex = nil

	for pairIndex, pairData in ipairs(Orderbook) do
		for orderIndex, order in ipairs(pairData.Orders) do
			if order.Type == 'english' and order.Id == orderId then
				targetOrder = order
				targetOrderIndex = orderIndex
				targetPairIndex = pairIndex
				break
			end
		end
		if targetOrder then break end
	end

	if not targetOrder then
		utils.handleError({
			Target = args.sender,
			Action = 'Settlement-Error',
			Message = 'Auction order not found',
			Quantity = '0',
			TransferToken = nil,
			OrderGroupId = args.orderGroupId
		})
		return
	end

	-- Check if auction has expired
	if isAuctionActive(targetOrder.ExpirationTime, args.timestamp) then
		utils.handleError({
			Target = args.sender,
			Action = 'Settlement-Error',
			Message = 'Auction has not expired yet',
			Quantity = '0',
			TransferToken = nil,
			OrderGroupId = args.orderGroupId
		})
		return
	end

	-- Execute the settlement
	-- For English auction settlement: seller gets ARIO tokens, buyer gets ANT tokens
	-- The Orderbook pair is [ANT_token_process, ARIO_token_process] 
	-- We need validPair to be [ARIO_token_process, ANT_token_process] for correct transfers
	local validPair = {Orderbook[targetPairIndex].Pair[2], Orderbook[targetPairIndex].Pair[1]} -- Swap the order to get [ARIO, ANT]
	local winningBidAmount = bint(auctionBids.HighestBid)
	local quantity = bint(targetOrder.Quantity)

	-- Calculate amounts after fees
	local calculatedSendAmount = utils.calculateSendAmount(winningBidAmount)
	local calculatedFillAmount = utils.calculateFillAmount(quantity)

	-- Execute token transfers
	utils.executeTokenTransfers({
		sender = auctionBids.HighestBidder,
		quantity = tostring(quantity),
		price = auctionBids.HighestBid,
		orderId = orderId,
		orderGroupId = args.orderGroupId,
		swapToken = targetOrder.Token -- ANT token process for the second transfer
	}, targetOrder, validPair, calculatedSendAmount, calculatedFillAmount)

	-- Record the settlement
	local settlement = {
		OrderId = orderId,
		Winner = auctionBids.HighestBidder,
		WinningBid = auctionBids.HighestBid,
		Quantity = tostring(quantity),
		Timestamp = args.timestamp,
		DominantToken = args.dominantToken,
		SwapToken = args.swapToken
	}

	-- Send settlement data to activity tracking
	local settlementDataSuccess, settlementData = pcall(function()
		return json.encode({
			Settlement = settlement
		})
	end)

	ao.send({
		Target = ACTIVITY_PROCESS,
		Action = 'Update-Auction-Settlement',
		Data = settlementDataSuccess and settlementData or ''
	})

	-- Remove the auction from orderbook
	table.remove(Orderbook[targetPairIndex].Orders, targetOrderIndex)

	-- Clear auction bids
	EnglishAuctionBids[orderId] = nil

	-- Notify winner
	ao.send({
		Target = auctionBids.HighestBidder,
		Action = 'Auction-Won',
		Tags = {
			Status = 'Success',
			OrderId = orderId,
			WinningBid = auctionBids.HighestBid,
			Quantity = tostring(quantity),
			Message = 'You won the English auction!',
			['X-Group-ID'] = args.orderGroupId
		}
	})

	-- Notify settler
	ao.send({
		Target = args.sender,
		Action = 'Settlement-Success',
		Tags = {
			Status = 'Success',
			OrderId = orderId,
			Winner = auctionBids.HighestBidder,
			WinningBid = auctionBids.HighestBid,
			Message = 'Auction settled successfully!',
			['X-Group-ID'] = args.orderGroupId
		}
	})
end

-- Helper function to get auction bid history
function english_auction.getBidHistory(args)
	local orderId = args.orderId
	local auctionBids = getAuctionBids(orderId)
	
	ao.send({
		Target = args.sender,
		Action = 'Bid-History',
		Tags = {
			OrderId = orderId,
			TotalBids = tostring(#auctionBids.Bids),
			HighestBid = auctionBids.HighestBid or '0',
			HighestBidder = auctionBids.HighestBidder or 'None'
		},
		Data = json.encode(auctionBids.Bids)
	})
end

-- Helper function to handle ARIO token orders: we are selling ANT token, so we need to add to orderbook
function english_auction.handleArioOrder(args, validPair, pairIndex)
	-- Add the new order to the orderbook (buy now functionality)
	table.insert(Orderbook[pairIndex].Orders, {
		Id = args.orderId,
		Quantity = tostring(args.quantity),
		OriginalQuantity = tostring(args.quantity),
		Creator = args.sender,
		Token = args.dominantToken,
		DateCreated = args.timestamp,
		Price = args.price and tostring(args.price),
		Type = 'english',
		Domain = args.domain,
		ExpirationTime = args.expirationTime and tostring(args.expirationTime) or nil
	})

	-- Send order data to activity tracking process
	local limitDataSuccess, limitData = pcall(function()
		return json.encode({
			Order = {
				Id = args.orderId,
				DominantToken = args.dominantToken,
				SwapToken = args.swapToken,
				Sender = args.sender,
				Receiver = nil,
				Quantity = tostring(args.quantity),
				Price = args.price and tostring(args.price),
				CreatedAt = args.timestamp,
				OrderType = 'english',
				Domain = args.domain,
				ExpirationTime = args.expirationTime and tostring(args.expirationTime) or nil
			}
		})
	end)

	ao.send({
		Target = ACTIVITY_PROCESS,
		Action = 'Update-Listed-Orders',
		Data = limitDataSuccess and limitData or ''
	})

	-- Notify sender of successful order creation
	ao.send({
		Target = args.sender,
		Action = 'Order-Success',
		Tags = {
			Status = 'Success',
			OrderId = args.orderId,
			Handler = 'Create-Order',
			DominantToken = args.dominantToken,
			SwapToken = args.swapToken,
			Quantity = tostring(args.quantity),
			Price = args.price and tostring(args.price),
			Message = 'ARIO order added to orderbook for English auction!',
			['X-Group-ID'] = args.orderGroupId,
			OrderType = 'english',
			Domain = args.domain,
			ExpirationTime = args.expirationTime and tostring(args.expirationTime) or nil
		}
	})
end

return english_auction
