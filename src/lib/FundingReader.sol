// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IPerplExchange} from "../interfaces/IPerplExchange.sol";

/// @title FundingReader
/// @notice Reads realised Perpl funding straight out of the exchange that
///         charged it. No oracle, no keeper, no reported price.
///
/// This is the whole trust story of PREMIA: the floating leg of a swap is not
/// an estimate of funding, it is the identical accumulator the trader's perp
/// position is settled against. A hedge built on it has zero basis by
/// construction.
library FundingReader {
    error WindowNotElapsed(uint256 startBlock, uint256 endBlock);
    error NoFundingData(uint256 marketId, uint256 blockNumber);

    /// @notice Realised funding per lot over a block window, and the number of
    ///         funding intervals actually spanned.
    /// @dev    Both endpoints snap down to the last funding event at or before
    ///         the given block, so `intervals` is derived from what the chain
    ///         actually recorded rather than from nominal calendar maths. A
    ///         fixed leg priced off `intervals` therefore cannot desync from
    ///         the floating leg, however late settlement is called.
    /// @return perLot   signed collateral per lot; positive means longs paid
    /// @return intervals funding events spanned
    function accrual(
        IPerplExchange exchange,
        uint256 marketId,
        uint256 startBlock,
        uint256 endBlock
    ) internal view returns (int256 perLot, uint256 intervals) {
        if (endBlock <= startBlock) revert WindowNotElapsed(startBlock, endBlock);

        (int256 s0, uint256 b0) = exchange.getFundingSumAtBlock(marketId, startBlock);
        (int256 s1, uint256 b1) = exchange.getFundingSumAtBlock(marketId, endBlock);

        if (b0 == 0) revert NoFundingData(marketId, startBlock);
        if (b1 == 0) revert NoFundingData(marketId, endBlock);

        perLot = s1 - s0;
        intervals = b1 > b0 ? (b1 - b0) / exchange.getFundingInterval() : 0;
    }
}
