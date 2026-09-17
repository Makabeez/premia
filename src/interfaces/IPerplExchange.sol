// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice Perpl exchange on Monad mainnet.
/// Proxy  0x34B6552d57a35a1D042CcAe1951BD1C370112a6F
/// Impl   0xf7df187620c81deee0833589509f41f95886cd33  (EIP-1967)
///
/// Selectors confirmed by scanning the implementation bytecode and resolving
/// against the public signature database, then exercised live via eth_call.
/// Return shapes are decoded from raw returndata — re-confirm against verified
/// source if Perpl publishes it.
interface IPerplExchange {
    /// @notice Cumulative funding product for a market, at the last funding
    ///         event at or before `blockNumber`.
    /// @dev    selector 0x7dd7e759. Returns the sum and the funding-event block
    ///         it snapped down to, so callers never need grid-aligned inputs.
    ///         Funding owed by a position of L lots between two blocks is
    ///         (sum_b - sum_a) * L, in collateral units per lot.
    function getFundingSumAtBlock(uint256 marketId, uint256 blockNumber)
        external view returns (int256 sum, uint256 atBlock);

    /// @notice Blocks between funding events. 8571 on mainnet (~2580s).
    /// @dev    selector 0x0d3e87a7
    function getFundingInterval() external view returns (uint256);

    /// @dev selector 0x12e8eb2c
    function getAccountByAddr(address account) external view returns (uint256);
}
