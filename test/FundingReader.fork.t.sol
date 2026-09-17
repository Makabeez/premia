// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {IPerplExchange} from "../src/interfaces/IPerplExchange.sol";
import {FundingReader} from "../src/lib/FundingReader.sol";

/// Every assertion below was first observed via raw eth_call against Monad
/// mainnet. If Perpl upgrades the implementation and these break, the swap's
/// settlement assumptions have changed and PREMIA must not be deployed until
/// they are re-derived.
contract FundingReaderForkTest is Test {
    using FundingReader for IPerplExchange;

    IPerplExchange constant PERPL =
        IPerplExchange(0x34B6552d57a35a1D042CcAe1951BD1C370112a6F);

    uint256 constant BTC = 1;
    uint256 constant ETH = 20;

    // Two adjacent BTC funding events.
    uint256 constant FEB_A = 101129229;
    uint256 constant FEB_B = 101137800;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("monad"), 102579854);
    }

    function test_FundingIntervalIsDocumentedValue() public view {
        assertEq(PERPL.getFundingInterval(), 8571);
    }

    function test_SumMatchesPublicApi() public view {
        (int256 sA, uint256 bA) = PERPL.getFundingSumAtBlock(BTC, FEB_A);
        (int256 sB, uint256 bB) = PERPL.getFundingSumAtBlock(BTC, FEB_B);
        assertEq(sA, -37174);
        assertEq(sB, -37144);
        assertEq(bA, FEB_A);
        assertEq(bB, FEB_B);
    }

    /// The delta across one interval must equal the per-lot payment the API
    /// reports for that event (`ppl` = 30). This is the identity the whole
    /// instrument rests on.
    function test_DeltaEqualsPaymentPerLot() public view {
        (int256 perLot, uint256 intervals) =
            PERPL.accrual(BTC, FEB_A, FEB_B);
        assertEq(perLot, 30);
        assertEq(intervals, 1);
    }

    /// Non-aligned blocks snap down to the previous funding event, so series
    /// can expire at any block height.
    function test_UnalignedBlockSnapsDown() public view {
        (int256 s, uint256 b) = PERPL.getFundingSumAtBlock(BTC, FEB_B + 1);
        assertEq(s, -37144);
        assertEq(b, FEB_B);
    }

    /// History reaches far enough back that no realistic swap tenor can fall
    /// off the end.
    function test_DeepHistoryAvailable() public view {
        (, uint256 b) = PERPL.getFundingSumAtBlock(BTC, 62579854);
        assertGt(b, 0);
    }

    function test_FundingCanBePositive() public view {
        (int256 s,) = PERPL.getFundingSumAtBlock(ETH, FEB_B);
        assertEq(s, 1600);
    }

    function test_RevertsOnInvertedWindow() public {
        vm.expectRevert();
        this.accrualExternal(BTC, FEB_B, FEB_A);
    }

    function accrualExternal(uint256 m, uint256 a, uint256 b)
        external view returns (int256, uint256)
    {
        return PERPL.accrual(m, a, b);
    }
}
