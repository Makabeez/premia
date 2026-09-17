// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {PremiaSwap, IERC20} from "../src/PremiaSwap.sol";
import {IPerplExchange} from "../src/interfaces/IPerplExchange.sol";
import {MockPerpl} from "./mocks/MockPerpl.sol";
import {MockAUSD} from "./mocks/MockAUSD.sol";

contract PremiaSwapTest is Test {
    MockPerpl perpl;
    MockAUSD ausd;
    PremiaSwap swap;

    address maker = address(0xA11CE);
    address taker = address(0xB0B);

    uint16 constant MKT = 50;              // ZEC — a launch market
    uint256 constant INTERVAL = 8571;
    uint64 constant START = 8571 * 100;    // on-grid
    uint64 constant END   = 8571 * 133;    // 33 intervals ~ 24h
    uint128 constant CAP  = 500;           // funding units per lot
    uint128 constant SCALE = 100_000;      // collateral wei per funding unit

    function setUp() public {
        perpl = new MockPerpl();
        ausd = new MockAUSD();
        swap = new PremiaSwap(IPerplExchange(address(perpl)), IERC20(address(ausd)));

        vm.roll(1000);
        ausd.mint(maker, 1e24);
        ausd.mint(taker, 1e24);
        vm.prank(maker); ausd.approve(address(swap), type(uint256).max);
        vm.prank(taker); ausd.approve(address(swap), type(uint256).max);
    }

    function _series() internal returns (uint256 id) {
        // tick 0 = 0 units, step 1 unit per interval
        id = swap.createSeries(MKT, START, END, 0, 1, CAP, SCALE);
    }

    /// realised funding of `total` units per lot across the window
    function _funding(int256 startSum, int256 endSum) internal {
        perpl.setFundingSum(MKT, START, startSum);
        perpl.setFundingSum(MKT, END, endSum);
    }

    // ------------------------------------------------------------ book logic

    function test_PostAndCancelRefundsEscrow() public {
        uint256 id = _series();
        uint256 before = ausd.balanceOf(maker);

        vm.prank(maker);
        swap.postQuote(id, PremiaSwap.Side.ReceiveFixed, 10, 4);
        assertEq(ausd.balanceOf(maker), before - uint256(CAP) * 4 * SCALE);

        vm.prank(maker);
        swap.cancelQuote(id, PremiaSwap.Side.ReceiveFixed, 10, 0);
        assertEq(ausd.balanceOf(maker), before);

        assertEq(swap.bitmap(id, PremiaSwap.Side.ReceiveFixed), 0);
    }

    /// A PayFixed taker must lift the CHEAPEST fixed rate on offer.
    function test_PricePriorityIsEnforcedByBitmap() public {
        uint256 id = _series();
        vm.startPrank(maker);
        swap.postQuote(id, PremiaSwap.Side.ReceiveFixed, 20, 1);
        swap.postQuote(id, PremiaSwap.Side.ReceiveFixed, 5,  1);  // cheaper
        swap.postQuote(id, PremiaSwap.Side.ReceiveFixed, 12, 1);
        vm.stopPrank();

        (bool ok, uint8 tick) = swap.bestTick(id, PremiaSwap.Side.ReceiveFixed);
        assertTrue(ok);
        assertEq(tick, 5);

        vm.prank(taker);
        swap.take(id, PremiaSwap.Side.PayFixed, 1, 255);

        PremiaSwap.Fill[] memory f = swap.fillsOf(id, taker);
        assertEq(f.length, 1);
        assertEq(f[0].k, 5);
    }

    /// A ReceiveFixed taker must hit the RICHEST bid.
    function test_ReceiveFixedTakerHitsHighestBid() public {
        uint256 id = _series();
        vm.startPrank(maker);
        swap.postQuote(id, PremiaSwap.Side.PayFixed, 3,  1);
        swap.postQuote(id, PremiaSwap.Side.PayFixed, 19, 1);  // richest
        vm.stopPrank();

        vm.prank(taker);
        swap.take(id, PremiaSwap.Side.ReceiveFixed, 1, 0);

        PremiaSwap.Fill[] memory f = swap.fillsOf(id, taker);
        assertEq(f[0].k, 19);
    }

    function test_TimePriorityWithinTick() public {
        uint256 id = _series();
        address maker2 = address(0xCAFE);
        ausd.mint(maker2, 1e24);
        vm.prank(maker2); ausd.approve(address(swap), type(uint256).max);

        vm.prank(maker);  swap.postQuote(id, PremiaSwap.Side.ReceiveFixed, 7, 1);
        vm.prank(maker2); swap.postQuote(id, PremiaSwap.Side.ReceiveFixed, 7, 1);

        vm.prank(taker);
        swap.take(id, PremiaSwap.Side.PayFixed, 1, 255);

        assertEq(swap.fillsOf(id, maker).length, 1);
        assertEq(swap.fillsOf(id, maker2).length, 0);
    }

    function test_LimitStopsTheWalk() public {
        uint256 id = _series();
        vm.prank(maker);
        swap.postQuote(id, PremiaSwap.Side.ReceiveFixed, 30, 1);

        vm.prank(taker);
        vm.expectRevert(PremiaSwap.NoLiquidity.selector);
        swap.take(id, PremiaSwap.Side.PayFixed, 1, 10);
    }

    function test_TradingClosesAtStartBlock() public {
        uint256 id = _series();
        vm.roll(START);
        vm.prank(maker);
        vm.expectRevert(PremiaSwap.TradingClosed.selector);
        swap.postQuote(id, PremiaSwap.Side.ReceiveFixed, 5, 1);
    }

    // ------------------------------------------------------------ settlement

    function test_IntervalsComeFromRecordedEvents() public {
        uint256 id = _series();
        _funding(1000, 1000);
        vm.roll(END + 1);
        swap.settle(id);
        assertEq(swap.getSeries(id).intervals, 33);
    }

    /// The whole point: a hedger's payout tracks realised funding exactly.
    function test_PayoutIsZeroSumAndTracksRealisedFunding() public {
        uint256 id = _series();

        vm.prank(maker);
        swap.postQuote(id, PremiaSwap.Side.ReceiveFixed, 4, 10); // k = 4/interval
        vm.prank(taker);
        swap.take(id, PremiaSwap.Side.PayFixed, 10, 255);

        // realised: 200 units per lot over 33 intervals (~6.06/interval)
        _funding(0, 200);
        vm.roll(END + 1);
        swap.settle(id);

        // fixed leg = 4 * 33 = 132. net to PayFixed = 200 - 132 = +68 per lot.
        int256 expectedNet = 68;
        uint256 takerPay = uint256(int256(uint256(CAP)) + expectedNet) * 10 * SCALE;
        uint256 makerPay = uint256(int256(uint256(CAP)) - expectedNet) * 10 * SCALE;

        assertEq(swap.quoteClaim(id, taker), takerPay);
        assertEq(swap.quoteClaim(id, maker), makerPay);

        uint256 potBefore = ausd.balanceOf(address(swap));
        vm.prank(taker); swap.claim(id);
        vm.prank(maker); swap.claim(id);

        assertEq(takerPay + makerPay, potBefore, "pot must drain exactly");
        assertEq(ausd.balanceOf(address(swap)), 0);
    }

    /// Negative funding (LIT territory) must flip the payout direction.
    function test_NegativeFundingPaysTheFixedReceiver() public {
        uint256 id = _series();
        vm.prank(maker); swap.postQuote(id, PremiaSwap.Side.ReceiveFixed, 0, 1);
        vm.prank(taker); swap.take(id, PremiaSwap.Side.PayFixed, 1, 255);

        _funding(0, -300);
        vm.roll(END + 1);
        swap.settle(id);

        assertEq(swap.quoteClaim(id, taker), uint256(int256(uint256(CAP)) - 300) * SCALE);
        assertEq(swap.quoteClaim(id, maker), uint256(int256(uint256(CAP)) + 300) * SCALE);
    }

    /// Solvency is structural: even an absurd funding print cannot drain more
    /// than was escrowed.
    function test_CapBoundsAnExtremePrint() public {
        uint256 id = _series();
        vm.prank(maker); swap.postQuote(id, PremiaSwap.Side.ReceiveFixed, 0, 1);
        vm.prank(taker); swap.take(id, PremiaSwap.Side.PayFixed, 1, 255);

        _funding(0, 10_000_000);
        vm.roll(END + 1);
        swap.settle(id);

        uint256 pot = ausd.balanceOf(address(swap));
        assertEq(swap.quoteClaim(id, taker), uint256(CAP) * 2 * SCALE);
        assertEq(swap.quoteClaim(id, maker), 0);

        vm.prank(taker); swap.claim(id);
        vm.prank(maker); swap.claim(id);
        assertEq(ausd.balanceOf(address(swap)), 0);
        assertEq(pot, uint256(CAP) * 2 * SCALE);
    }

    function test_PartialFillRefundsUntradedEscrow() public {
        uint256 id = _series();
        vm.prank(maker); swap.postQuote(id, PremiaSwap.Side.ReceiveFixed, 5, 3);

        uint256 before = ausd.balanceOf(taker);
        vm.prank(taker); swap.take(id, PremiaSwap.Side.PayFixed, 10, 255);

        // only 3 lots existed; escrow for 7 comes straight back
        assertEq(ausd.balanceOf(taker), before - uint256(CAP) * 3 * SCALE);
    }

    function test_CannotSettleEarlyOrTwice() public {
        uint256 id = _series();
        _funding(0, 100);
        vm.expectRevert(PremiaSwap.NotExpired.selector);
        swap.settle(id);

        vm.roll(END + 1);
        swap.settle(id);
        vm.expectRevert(PremiaSwap.AlreadySettled.selector);
        swap.settle(id);
    }

    function test_CannotClaimTwice() public {
        uint256 id = _series();
        vm.prank(maker); swap.postQuote(id, PremiaSwap.Side.ReceiveFixed, 5, 1);
        vm.prank(taker); swap.take(id, PremiaSwap.Side.PayFixed, 1, 255);
        _funding(0, 100);
        vm.roll(END + 1);
        swap.settle(id);

        vm.prank(taker); swap.claim(id);
        vm.prank(taker);
        vm.expectRevert(PremiaSwap.AlreadyClaimed.selector);
        swap.claim(id);
    }

    /// Settlement must be callable by a stranger, long after expiry, and give
    /// the same answer — the historical getter is what makes this safe.
    function test_LateSettlementByStrangerIsIdentical() public {
        uint256 id = _series();
        vm.prank(maker); swap.postQuote(id, PremiaSwap.Side.ReceiveFixed, 5, 1);
        vm.prank(taker); swap.take(id, PremiaSwap.Side.PayFixed, 1, 255);
        _funding(0, 150);

        // funding keeps accruing well past expiry
        perpl.setFundingSum(MKT, 8571 * 300, 99999);

        vm.roll(8571 * 400);
        vm.prank(address(0xDEAD));
        swap.settle(id);

        assertEq(swap.getSeries(id).netPerLot, 150, "must read the window, not HEAD");
        assertEq(swap.getSeries(id).intervals, 33);
    }

    function testFuzz_PotAlwaysDrainsToZero(int128 endSum, uint8 tick, uint8 lots) public {
        vm.assume(lots > 0);
        uint256 id = _series();

        vm.prank(maker); swap.postQuote(id, PremiaSwap.Side.ReceiveFixed, tick, lots);
        vm.prank(taker); swap.take(id, PremiaSwap.Side.PayFixed, lots, 255);

        _funding(0, endSum);
        vm.roll(END + 1);
        swap.settle(id);

        uint256 pot = ausd.balanceOf(address(swap));
        vm.prank(taker); swap.claim(id);
        vm.prank(maker); swap.claim(id);

        assertEq(ausd.balanceOf(address(swap)), 0, "pot must fully drain");
        assertEq(pot, uint256(CAP) * 2 * uint256(lots) * SCALE);
    }
}
